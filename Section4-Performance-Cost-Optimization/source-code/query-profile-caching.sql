-- =============================================================================
-- LAB - Query Profile, warehouse cache and result cache
-- Section 4: Performance & Cost Optimization
-- Run in a Snowsight worksheet as ACCOUNTADMIN. View each Query Profile in the
-- UI: open the query from Monitoring, then the Query Profile tab.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;

-- The warehouse cache lives on the warehouse's local disk, and it is wiped the
-- moment the warehouse suspends. Reading a Query Profile between our two runs
-- takes longer than the default 60s auto-suspend, which would suspend COURSE_WH
-- and wipe the cache mid-demo. So we raise auto-suspend to keep it awake, then
-- suspend and resume once to force a clean cold start.
ALTER WAREHOUSE COURSE_WH SET AUTO_SUSPEND = 600;
ALTER WAREHOUSE COURSE_WH SUSPEND;
ALTER WAREHOUSE COURSE_WH RESUME;

-- USE_CACHED_RESULT is the switch for the result cache. Off, so the query runs.
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- RUN 1 (cold). Open the Query Profile. Statistics: Partitions scanned equals
-- Partitions total (no WHERE to prune), and Percentage scanned from cache reads
-- 0 - everything came from storage.
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- RUN 2 (warm) - THE WAREHOUSE CACHE. Same query, still executing for real.
-- Percentage scanned from cache now reads 100: run 1 left the data on the
-- warehouse local disk, so run 2 read it from there instead of storage.
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- RUN 3 - THE RESULT CACHE. Turn the result cache on and run the same query. The
-- profile collapses to one QUERY RESULT REUSE node: zero bytes, no warehouse. The
-- query does not run at all - Snowflake hands back the saved answer.
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- Put auto-suspend back to a thrifty value.
ALTER WAREHOUSE COURSE_WH SET AUTO_SUSPEND = 60;
