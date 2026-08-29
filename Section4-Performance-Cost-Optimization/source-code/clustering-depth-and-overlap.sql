-- =============================================================================
-- LAB - Clustering depth and partition overlap
-- Section 4: Performance & Cost Optimization
-- Run top to bottom in a Snowsight worksheet. Role ACCOUNTADMIN.
-- We measure overlap and depth on a real table, then fix it with a clustering key.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS PERF_LAB;
CREATE SCHEMA   IF NOT EXISTS PERF_LAB.PERF;
USE SCHEMA PERF_LAB.PERF;

-- 1. Copy a real, large table. It loads in its natural order (by order key),
--    NOT by date, so it should be badly clustered on the order date.
CREATE OR REPLACE TABLE orders AS
SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

-- 2. Ask Snowflake for the clustering picture on o_orderdate. Read three fields
--    in the JSON it returns:
--      average_overlaps         -> how many other partitions each one overlaps
--      average_depth            -> the headline number, lower is better
--      partition_depth_histogram-> how many partitions sit at each depth level
--    On this natural-order table expect high overlap and high depth.
SELECT SYSTEM$CLUSTERING_INFORMATION('orders', '(o_orderdate)');

-- 3. Now make a copy that is physically sorted by o_orderdate, and look again.
--    The ranges stop overlapping, so average_overlaps and average_depth collapse.
CREATE OR REPLACE TABLE orders_sorted AS
SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS ORDER BY o_orderdate;
SELECT SYSTEM$CLUSTERING_INFORMATION('orders_sorted', '(o_orderdate)');

-- 4. If you only want the single depth number, there is a shorthand.
SELECT SYSTEM$CLUSTERING_DEPTH('orders', '(o_orderdate)')        AS depth_natural;
SELECT SYSTEM$CLUSTERING_DEPTH('orders_sorted', '(o_orderdate)') AS depth_sorted;

-- 5. In real life you do not keep a hand-sorted copy. You declare a clustering
--    key, and Snowflake keeps the table clustered in the background as data lands.
ALTER TABLE orders CLUSTER BY (o_orderdate);
SHOW TABLES LIKE 'orders';   -- the cluster_by column now reads LINEAR(O_ORDERDATE)

-- 6. The payoff: a date-filtered query reads far fewer micro-partitions on the
--    well-clustered data. Run both, then open the Query Profile on each and
--    compare "Partitions scanned" against "Partitions total".
SELECT COUNT(*) FROM orders_sorted WHERE o_orderdate BETWEEN '1995-01-01' AND '1995-01-31';
SELECT COUNT(*) FROM orders        WHERE o_orderdate BETWEEN '1995-01-01' AND '1995-01-31';

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP TABLE IF EXISTS orders;
-- DROP TABLE IF EXISTS orders_sorted;
