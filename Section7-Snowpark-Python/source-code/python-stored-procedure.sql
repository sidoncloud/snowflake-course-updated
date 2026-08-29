-- =============================================================================
-- LAB - Deploy and Schedule a Python Stored Procedure
-- Section 7: Snowpark, Data Engineering in Python
--
-- We build the pattern a real data team actually schedules: an incremental
-- roll-up. New orders land in a raw table throughout the day. A Snowpark Python
-- stored procedure runs on a schedule, reads a watermark to find only the rows
-- that arrived since its last run, aggregates just that new batch into a curated
-- sales-analytics table, and advances the watermark. Re-running it does nothing
-- until fresh data shows up, so the job is safe to fire every few minutes.
--
-- The procedure takes no business parameters. It figures out what to process
-- from the watermark, which is why the scheduled task can call it with no
-- arguments and still do the right thing on every run.
--
-- Run it in a Snowsight worksheet. No credentials needed. We seed the raw table
-- from SNOWFLAKE_SAMPLE_DATA so there is nothing to upload.
-- =============================================================================

-- 1. A home for the lab. A dedicated database and schema keep everything isolated.
CREATE DATABASE IF NOT EXISTS SNOWPARK_SPROC_LAB;
CREATE SCHEMA IF NOT EXISTS SNOWPARK_SPROC_LAB.ANALYTICS;
USE SCHEMA SNOWPARK_SPROC_LAB.ANALYTICS;
USE WAREHOUSE COURSE_WH;

-- 2. The raw landing table: one row per order, with LOAD_TS stamped when the
--    row arrived. We load it by hand in this lab so everything is self-contained.
--    The watermark works off LOAD_TS, not the business order date, because what
--    matters to a scheduled job is when data landed, not when the order was placed.
CREATE OR REPLACE TABLE ORDERS_RAW (
    order_key      NUMBER,
    region         STRING,
    market_segment STRING,
    customer_name  STRING,
    net_revenue    NUMBER(18,2),
    discount_given NUMBER(18,2),
    is_late        NUMBER(1,0),
    order_date     DATE,
    load_ts        TIMESTAMP_NTZ
);

-- 3. The curated targets the procedure maintains.
--
--    SALES_SUMMARY holds additive running totals, one row per region and market
--    segment. We store the building blocks the aggregation can accumulate, such
--    as order_count and late_order_count, and derive the ratios in a view. That
--    keeps the incremental MERGE correct: you can add two order counts, but you
--    cannot add two averages.
CREATE OR REPLACE TABLE SALES_SUMMARY (
    region           STRING,
    market_segment   STRING,
    order_count      NUMBER,
    late_order_count NUMBER,
    net_revenue      NUMBER(18,2),
    discount_given   NUMBER(18,2),
    last_refreshed_at TIMESTAMP_NTZ
);

--    CUSTOMER_REVENUE is the running revenue per customer, also accumulated with
--    a MERGE. TOP_CUSTOMERS is rebuilt from it each run with a window rank.
CREATE OR REPLACE TABLE CUSTOMER_REVENUE (
    region         STRING,
    market_segment STRING,
    customer_name  STRING,
    net_revenue    NUMBER(18,2)
);

CREATE OR REPLACE TABLE TOP_CUSTOMERS (
    region         STRING,
    market_segment STRING,
    customer_name  STRING,
    net_revenue    NUMBER(18,2),
    revenue_rank   NUMBER,
    refreshed_at   TIMESTAMP_NTZ
);

-- 4. The watermark control table. One row that remembers the LOAD_TS of the last
--    batch this pipeline processed. We seed it far in the past so the very first
--    run picks up everything.
CREATE OR REPLACE TABLE PIPELINE_WATERMARK (
    pipeline_name STRING,
    last_load_ts  TIMESTAMP_NTZ,
    updated_at    TIMESTAMP_NTZ
);
INSERT INTO PIPELINE_WATERMARK (pipeline_name, last_load_ts, updated_at)
    VALUES ('SALES_ANALYTICS', '1900-01-01'::TIMESTAMP_NTZ, CURRENT_TIMESTAMP());

-- 5. An audit table. Every run appends a row: the watermark it started from, the
--    watermark it advanced to, how many rows it processed, and its status.
CREATE OR REPLACE TABLE REFRESH_AUDIT (
    run_id         STRING,
    run_ts         TIMESTAMP_NTZ,
    watermark_from TIMESTAMP_NTZ,
    watermark_to   TIMESTAMP_NTZ,
    rows_processed NUMBER,
    status         STRING
);

-- 6. Seed the first batch of raw orders. This stands in for an overnight load.
--    We roll SNOWFLAKE_SAMPLE_DATA up to order grain and land one month of
--    orders. Every row in this INSERT gets the same LOAD_TS, so they form one
--    batch the watermark can track as a unit.
INSERT INTO ORDERS_RAW
SELECT
    o.O_ORDERKEY,
    r.R_NAME,
    c.C_MKTSEGMENT,
    c.C_NAME,
    ROUND(SUM(l.L_EXTENDEDPRICE * (1 - l.L_DISCOUNT)), 2),
    ROUND(SUM(l.L_EXTENDEDPRICE * l.L_DISCOUNT), 2),
    MAX(IFF(l.L_RECEIPTDATE > l.L_COMMITDATE, 1, 0)),
    o.O_ORDERDATE,
    CURRENT_TIMESTAMP()
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM  l
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS    o ON l.L_ORDERKEY  = o.O_ORDERKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER  c ON o.O_CUSTKEY   = c.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION    n ON c.C_NATIONKEY = n.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION    r ON n.N_REGIONKEY = r.R_REGIONKEY
WHERE o.O_ORDERDATE >= '1996-01-01' AND o.O_ORDERDATE < '1996-02-01'
GROUP BY o.O_ORDERKEY, r.R_NAME, c.C_MKTSEGMENT, c.C_NAME, o.O_ORDERDATE;

SELECT COUNT(*) AS batch_1_rows FROM ORDERS_RAW;

-- 7. The procedure. LANGUAGE PYTHON with a Snowpark handler named run, and no
--    business parameters. This is where Python earns its place over a single SQL
--    statement: it reads the watermark, decides whether there is anything to do,
--    exits early and cleanly when there is not, accumulates several targets in
--    sequence, advances the watermark, and returns a run summary string. That is
--    control flow and orchestration, not one query a task could run on its own.
CREATE OR REPLACE PROCEDURE REFRESH_SALES_ANALYTICS()
    RETURNS STRING
    LANGUAGE PYTHON
    RUNTIME_VERSION = '3.11'
    PACKAGES = ('snowflake-snowpark-python')
    HANDLER = 'run'
AS
$$
import uuid
from snowflake.snowpark.functions import (
    col, sum as sum_, count as count_, max as max_, iff, lit,
    current_timestamp, round as round_, rank,
    when_matched, when_not_matched,
)
from snowflake.snowpark import Window

PIPELINE = "SALES_ANALYTICS"
TOP_N = 5

def run(session):
    run_id = str(uuid.uuid4())
    try:
        # Read the watermark: the LOAD_TS of the last batch we processed.
        wm_from = (session.table("PIPELINE_WATERMARK")
                   .filter(col("PIPELINE_NAME") == lit(PIPELINE))
                   .select("LAST_LOAD_TS").collect()[0][0])

        # The new batch is every raw row that landed after the watermark.
        new_rows = session.table("ORDERS_RAW").filter(col("LOAD_TS") > lit(wm_from))
        new_rows.cache_result()
        row_count = new_rows.count()

        # Nothing new. Log it, leave the targets untouched, and return. A
        # scheduled job fires on a clock, not on data, so most runs land here.
        if row_count == 0:
            (session.create_dataframe(
                [[run_id, str(wm_from), str(wm_from), 0, "NO_NEW_DATA"]],
                schema=["RUN_ID", "WATERMARK_FROM", "WATERMARK_TO",
                        "ROWS_PROCESSED", "STATUS"])
             .select("RUN_ID", current_timestamp().as_("RUN_TS"),
                     col("WATERMARK_FROM").cast("timestamp_ntz").as_("WATERMARK_FROM"),
                     col("WATERMARK_TO").cast("timestamp_ntz").as_("WATERMARK_TO"),
                     "ROWS_PROCESSED", "STATUS")
             .write.mode("append").save_as_table("REFRESH_AUDIT"))
            return f"No new data since {wm_from}. Nothing to process."

        # The high-water mark of this batch is the newest LOAD_TS in it. We will
        # advance the watermark to exactly this once the work succeeds.
        wm_to = new_rows.select(max_(col("LOAD_TS"))).collect()[0][0]

        # Aggregate the new batch to region and segment deltas.
        seg_delta = (new_rows.group_by(col("REGION"), col("MARKET_SEGMENT"))
            .agg(
                count_(col("ORDER_KEY")).as_("ORDER_COUNT"),
                sum_(col("IS_LATE")).as_("LATE_ORDER_COUNT"),
                round_(sum_(col("NET_REVENUE")), 2).as_("NET_REVENUE"),
                round_(sum_(col("DISCOUNT_GIVEN")), 2).as_("DISCOUNT_GIVEN"),
            ))

        # MERGE the deltas into the running summary. When the region and segment
        # already exist we add the new batch onto the existing totals; when they
        # are new we insert them. Adding onto stored totals is why re-running on
        # the same batch cannot happen: the watermark filtered that batch out.
        summary = session.table("SALES_SUMMARY")
        summary.merge(
            seg_delta,
            (summary["REGION"] == seg_delta["REGION"]) &
            (summary["MARKET_SEGMENT"] == seg_delta["MARKET_SEGMENT"]),
            [
                when_matched().update({
                    "ORDER_COUNT": summary["ORDER_COUNT"] + seg_delta["ORDER_COUNT"],
                    "LATE_ORDER_COUNT": summary["LATE_ORDER_COUNT"] + seg_delta["LATE_ORDER_COUNT"],
                    "NET_REVENUE": summary["NET_REVENUE"] + seg_delta["NET_REVENUE"],
                    "DISCOUNT_GIVEN": summary["DISCOUNT_GIVEN"] + seg_delta["DISCOUNT_GIVEN"],
                    "LAST_REFRESHED_AT": current_timestamp(),
                }),
                when_not_matched().insert({
                    "REGION": seg_delta["REGION"],
                    "MARKET_SEGMENT": seg_delta["MARKET_SEGMENT"],
                    "ORDER_COUNT": seg_delta["ORDER_COUNT"],
                    "LATE_ORDER_COUNT": seg_delta["LATE_ORDER_COUNT"],
                    "NET_REVENUE": seg_delta["NET_REVENUE"],
                    "DISCOUNT_GIVEN": seg_delta["DISCOUNT_GIVEN"],
                    "LAST_REFRESHED_AT": current_timestamp(),
                }),
            ],
        )

        # Accumulate revenue per customer the same additive way.
        cust_delta = (new_rows.group_by(
                col("REGION"), col("MARKET_SEGMENT"), col("CUSTOMER_NAME"))
            .agg(round_(sum_(col("NET_REVENUE")), 2).as_("NET_REVENUE")))
        cust_run = session.table("CUSTOMER_REVENUE")
        cust_run.merge(
            cust_delta,
            (cust_run["REGION"] == cust_delta["REGION"]) &
            (cust_run["MARKET_SEGMENT"] == cust_delta["MARKET_SEGMENT"]) &
            (cust_run["CUSTOMER_NAME"] == cust_delta["CUSTOMER_NAME"]),
            [
                when_matched().update({
                    "NET_REVENUE": cust_run["NET_REVENUE"] + cust_delta["NET_REVENUE"],
                }),
                when_not_matched().insert({
                    "REGION": cust_delta["REGION"],
                    "MARKET_SEGMENT": cust_delta["MARKET_SEGMENT"],
                    "CUSTOMER_NAME": cust_delta["CUSTOMER_NAME"],
                    "NET_REVENUE": cust_delta["NET_REVENUE"],
                }),
            ],
        )

        # Rebuild the leaderboard from the full running revenue with a window
        # rank, so it always reflects cumulative totals, not just this batch.
        w = (Window.partition_by(col("REGION"), col("MARKET_SEGMENT"))
                   .order_by(col("NET_REVENUE").desc()))
        top = (session.table("CUSTOMER_REVENUE")
            .with_column("REVENUE_RANK", rank().over(w))
            .filter(col("REVENUE_RANK") <= TOP_N)
            .with_column("REFRESHED_AT", current_timestamp()))
        top.write.mode("overwrite").save_as_table("TOP_CUSTOMERS")

        # Advance the watermark to this batch's high-water mark. Only now, after
        # the writes succeeded, so a failure leaves the watermark where it was and
        # the batch is retried next run.
        (session.table("PIPELINE_WATERMARK")
            .update({"LAST_LOAD_TS": lit(wm_to),
                     "UPDATED_AT": current_timestamp()},
                    col("PIPELINE_NAME") == lit(PIPELINE)))

        # Audit the successful run.
        (session.create_dataframe(
            [[run_id, str(wm_from), str(wm_to), int(row_count), "SUCCESS"]],
            schema=["RUN_ID", "WATERMARK_FROM", "WATERMARK_TO",
                    "ROWS_PROCESSED", "STATUS"])
         .select("RUN_ID", current_timestamp().as_("RUN_TS"),
                 col("WATERMARK_FROM").cast("timestamp_ntz").as_("WATERMARK_FROM"),
                 col("WATERMARK_TO").cast("timestamp_ntz").as_("WATERMARK_TO"),
                 "ROWS_PROCESSED", "STATUS")
         .write.mode("append").save_as_table("REFRESH_AUDIT"))

        return (f"Processed {row_count} new rows from {wm_from} to {wm_to}, "
                f"run_id={run_id}")

    except Exception as e:
        # Record a FAILED audit row so the run is never silent, then re-raise so
        # the caller and the task both see the error. The watermark was not
        # advanced, so the batch is reprocessed on the next run.
        (session.create_dataframe(
            [[run_id, 0, f"FAILED: {str(e)[:200]}"]],
            schema=["RUN_ID", "ROWS_PROCESSED", "STATUS"])
         .select("RUN_ID", current_timestamp().as_("RUN_TS"),
                 lit(None).cast("timestamp_ntz").as_("WATERMARK_FROM"),
                 lit(None).cast("timestamp_ntz").as_("WATERMARK_TO"),
                 "ROWS_PROCESSED", "STATUS")
         .write.mode("append").save_as_table("REFRESH_AUDIT"))
        raise
$$;

-- 8. Confirm the procedure is deployed as a permanent object in the schema.
SHOW PROCEDURES LIKE 'REFRESH_SALES_ANALYTICS';

-- 9. First run by hand. The watermark is still at 1900, so this processes the
--    whole first batch. Notice we call it with no arguments.
CALL REFRESH_SALES_ANALYTICS();

-- Inspect what it wrote. The summary carries running totals; the view derives the
-- ratios the business reads.
CREATE OR REPLACE VIEW SALES_SUMMARY_V AS
SELECT region, market_segment, order_count, net_revenue, discount_given,
       ROUND(net_revenue / NULLIF(order_count, 0), 2)      AS avg_order_value,
       ROUND(late_order_count / NULLIF(order_count, 0), 4) AS late_ship_rate,
       last_refreshed_at
FROM SALES_SUMMARY;

SELECT * FROM SALES_SUMMARY_V ORDER BY net_revenue DESC;
SELECT * FROM TOP_CUSTOMERS ORDER BY region, market_segment, revenue_rank;

-- The watermark has moved off 1900 to the first batch's load time.
SELECT * FROM PIPELINE_WATERMARK;
SELECT * FROM REFRESH_AUDIT ORDER BY run_ts DESC;

-- 10. Run it again immediately, with no new data. The watermark already covers
--     everything in ORDERS_RAW, so this run finds nothing, writes a NO_NEW_DATA
--     audit row, and leaves the totals exactly where they were. That is the
--     idempotency a scheduled job depends on.
CALL REFRESH_SALES_ANALYTICS();
SELECT status, rows_processed FROM REFRESH_AUDIT ORDER BY run_ts DESC LIMIT 1;

-- 11. A second batch lands. This is the next month of orders, standing in for the
--     next scheduled load. It gets a fresh LOAD_TS, later than batch one.
INSERT INTO ORDERS_RAW
SELECT
    o.O_ORDERKEY,
    r.R_NAME,
    c.C_MKTSEGMENT,
    c.C_NAME,
    ROUND(SUM(l.L_EXTENDEDPRICE * (1 - l.L_DISCOUNT)), 2),
    ROUND(SUM(l.L_EXTENDEDPRICE * l.L_DISCOUNT), 2),
    MAX(IFF(l.L_RECEIPTDATE > l.L_COMMITDATE, 1, 0)),
    o.O_ORDERDATE,
    CURRENT_TIMESTAMP()
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM  l
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS    o ON l.L_ORDERKEY  = o.O_ORDERKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER  c ON o.O_CUSTKEY   = c.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION    n ON c.C_NATIONKEY = n.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION    r ON n.N_REGIONKEY = r.R_REGIONKEY
WHERE o.O_ORDERDATE >= '1996-02-01' AND o.O_ORDERDATE < '1996-03-01'
GROUP BY o.O_ORDERKEY, r.R_NAME, c.C_MKTSEGMENT, c.C_NAME, o.O_ORDERDATE;

-- 12. Run once more. Now it processes only the second batch. The rows_processed
--     in the audit equals the second batch size, not the whole table, and the
--     summary totals grow by that batch. That is the incremental win: the job
--     never reprocesses what it already handled.
SELECT COUNT(*) AS total_raw_rows FROM ORDERS_RAW;
CALL REFRESH_SALES_ANALYTICS();
SELECT run_ts, watermark_from, watermark_to, rows_processed, status
FROM REFRESH_AUDIT ORDER BY run_ts DESC LIMIT 3;
SELECT * FROM SALES_SUMMARY_V ORDER BY net_revenue DESC;

-- 13. Deploy it on a schedule. The task wraps the CALL and runs it server-side.
--     The body is CALL with no arguments, because the procedure decides what to
--     process from the watermark. A real deployment might run this every few
--     minutes; we use a short interval so the point is easy to see.
CREATE OR REPLACE TASK REFRESH_SALES_TASK
    WAREHOUSE = COURSE_WH
    SCHEDULE  = '5 MINUTE'
AS
    CALL REFRESH_SALES_ANALYTICS();

-- A new task is created suspended, so it does not run yet.
SHOW TASKS LIKE 'REFRESH_SALES_TASK';

-- 14. Resume the task to make it live, then trigger one run now rather than
--     waiting for the schedule. Because there is no new data, this scheduled run
--     will log NO_NEW_DATA, which is exactly what a healthy idle pipeline does.
ALTER TASK REFRESH_SALES_TASK RESUME;
EXECUTE TASK REFRESH_SALES_TASK;

-- 15. Watch it in TASK_HISTORY. Re-run this over the next minute until you see
--     SUCCEEDED, and read the return_value the procedure handed back.
SELECT name, state, scheduled_time, completed_time, return_value, error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'REFRESH_SALES_TASK'))
ORDER BY scheduled_time DESC
LIMIT 5;

SELECT status, rows_processed FROM REFRESH_AUDIT ORDER BY run_ts DESC LIMIT 1;

-- 16. Teardown so the task never burns credits after the lab. Suspend it first,
--     then drop it.
ALTER TASK REFRESH_SALES_TASK SUSPEND;
DROP TASK IF EXISTS REFRESH_SALES_TASK;

-- Cleanup (optional, run this when you are done to remove everything the lab created):
--   DROP DATABASE IF EXISTS SNOWPARK_SPROC_LAB;
