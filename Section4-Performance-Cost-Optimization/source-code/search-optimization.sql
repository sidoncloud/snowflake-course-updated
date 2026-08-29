-- =============================================================================
-- LAB - The Search Optimization Service
-- Section 4: Performance & Cost Optimization
-- Run in a Snowsight worksheet as ACCOUNTADMIN.
-- A needle-in-a-haystack lookup scans the whole table. We switch on search
-- optimization and watch it read almost nothing.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS PERF_LAB;
CREATE SCHEMA   IF NOT EXISTS PERF_LAB.PERF;
USE SCHEMA PERF_LAB.PERF;

-- 1. Build a big table, 20 million rows, with a random, scattered event_id.
--    Because the id is random, its values land in every micro partition, so
--    normal pruning cannot skip anything on a lookup. That is exactly where
--    search optimization earns its keep.
CREATE OR REPLACE TABLE events AS
SELECT UNIFORM(1, 1000000000000, RANDOM()) AS event_id,
       RANDSTR(80, RANDOM())               AS payload
FROM TABLE(GENERATOR(ROWCOUNT => 20000000));

-- 2. Grab one real id to look up, and turn the result cache off so each run
--    actually executes.
SET eid = (SELECT event_id FROM events LIMIT 1);
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- 3. BEFORE. Look up that one id, then open its Query Profile. Read Partitions
--    scanned against Partitions total: they are equal, so it scanned the whole
--    table to find a single row.
SELECT COUNT(*) FROM events WHERE event_id = $eid;

-- 4. Switch on search optimization for equality lookups on event_id. Snowflake
--    builds a search access path for the column in the background.
ALTER TABLE events ADD SEARCH OPTIMIZATION ON EQUALITY(event_id);

-- 5. Watch the build with SHOW TABLES. search_optimization reads ON,
--    search_optimization_progress climbs to 100, and search_optimization_bytes
--    is how much storage the access path uses. Wait for 100 before the next step.
SHOW TABLES LIKE 'events';

-- 6. AFTER. Run the exact same lookup and open its Query Profile. The scan node is
--    now Search Optimization Access, and Partitions scanned is a tiny fraction of
--    the total, because the access path jumped straight to the partition holding
--    that id. Same query, same answer, almost no work.
SELECT COUNT(*) FROM events WHERE event_id = $eid;

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- ALTER TABLE events DROP SEARCH OPTIMIZATION;
-- DROP TABLE IF EXISTS events;
