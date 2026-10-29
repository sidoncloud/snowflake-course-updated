-- =============================================================================
-- TripLedger: Performance and Cost Optimization Assignment (starter)
--
-- Run in a Snowsight SQL worksheet as ACCOUNTADMIN.
-- The setup block builds the data for you. Each TASK section has TODO notes,
-- hints, and the slow query you are asked to fix. Write your own SQL under
-- each one.
-- =============================================================================


-- =============================================================================
-- SETUP (given)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- SMALL, because this lab scans and generates millions of rows.
CREATE WAREHOUSE IF NOT EXISTS TRIP_PERF_WH
  WAREHOUSE_SIZE      = 'SMALL'
  AUTO_SUSPEND        = 60
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'TripLedger: performance and cost optimization assignment';
USE WAREHOUSE TRIP_PERF_WH;

CREATE DATABASE IF NOT EXISTS TRIPLEDGER;
CREATE SCHEMA   IF NOT EXISTS TRIPLEDGER.PERF;
USE SCHEMA TRIPLEDGER.PERF;

-- TripLedger's trip history: 1,500,000 trips, copied from the free TPCH
-- sample data that ships with every Snowflake account, renamed to our domain.
CREATE OR REPLACE TABLE trips AS
SELECT
    o_orderkey      AS trip_id,
    o_custkey       AS rider_id,
    o_orderdate     AS trip_date,
    o_totalprice    AS fare_usd,
    o_orderpriority AS priority
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

SELECT COUNT(*) AS trip_count FROM trips;


-- =============================================================================
-- TASK 1: Measure how well the trips table is laid out for date-range reports
-- =============================================================================
-- TODO: Ask Snowflake how well trips is clustered on trip_date.
-- TODO: Read every field it returns and write down what each one means for a
--       report that filters on a date range.
-- Hint: clustering depth and overlap, Section 4.



-- =============================================================================
-- TASK 2: Fix the layout so a monthly report reads only what it needs
-- =============================================================================
-- The monthly report finance runs (given). Today it reads almost every
-- micro-partition of trips.
SELECT COUNT(*) FROM trips WHERE trip_date BETWEEN '1995-01-01' AND '1995-01-31';

-- TODO: Build a copy of trips that is physically sorted by trip_date, named
--       trips_sorted, and measure its clustering the same way as Task 1.
-- TODO: Run the monthly report against both tables and compare how much each
--       one reads.
-- TODO: Make the fix permanent on trips itself, so new data stays well laid out
--       without a hand-made copy.
-- Hint: micro-partitions, pruning and clustering keys, Section 4.



-- =============================================================================
-- TASK 3: Show the difference between the warehouse cache and the result cache
-- =============================================================================
-- The dashboard query (given).
SELECT priority, COUNT(*) AS trip_count, SUM(fare_usd) AS revenue
FROM trips
GROUP BY priority;

-- TODO: Run the dashboard query cold, then warm with the query still really
--       executing, then a third time where it does not execute at all.
-- TODO: For each run, note what the Query Profile shows.
-- TODO: Leave the warehouse settings the way you found them when you are done.
-- Hint: Query Profile and caching, Section 4. Think about what wipes each cache
--       and which session setting controls one of them.



-- =============================================================================
-- TASK 4: Make the single-trip lookup fast on twenty million rows
-- =============================================================================
-- DATA FOR THIS TASK (given). Support agents look up one trip by ride_ref, a
-- random identifier, so its values land in every micro-partition. This builds
-- 20 million rows and takes a little while on a SMALL warehouse.
CREATE OR REPLACE TABLE ride_lookup AS
SELECT UNIFORM(1, 1000000000000, RANDOM()) AS ride_ref,
       RANDSTR(80, RANDOM())               AS trip_payload
FROM TABLE(GENERATOR(ROWCOUNT => 20000000));

-- Pick one real ride_ref to look up.
SET rref = (SELECT ride_ref FROM ride_lookup LIMIT 1);

-- The lookup support runs (given). Today it scans the whole table.
SELECT COUNT(*) FROM ride_lookup WHERE ride_ref = $rref;

-- TODO: Make sure each run really executes, so your comparison is fair.
-- TODO: Make this equality lookup fast without changing the query.
-- TODO: Check that the feature has finished building before you measure again.
-- Hint: the search optimization service, Section 4.



-- =============================================================================
-- TASK 5: Find out what each warehouse actually cost
-- =============================================================================
-- TODO: Show the credits each warehouse used, most recent first.
-- TODO: Note any feature you turned on in this lab that keeps costing money
--       even when nobody uses it.
-- Hint: cost optimization patterns, Section 4, and the ACCOUNT_USAGE views in
--       the SNOWFLAKE database, Section 2. ACCOUNT_USAGE can lag by a few hours.



-- =============================================================================
-- TASK 6: Prove every fix with numbers from Query Profile
-- =============================================================================
-- TODO: Fill in the table below from the Query Profile of each run.
--       Do not copy numbers from anyone else, they change from run to run.
--
--   Run                              | Partitions scanned | Partitions total | Notes
--   ---------------------------------|--------------------|------------------|------
--   Monthly report on trips          |                    |                  |
--   Monthly report on trips_sorted   |                    |                  |
--   Dashboard query, cold            |                    |                  |
--   Dashboard query, warm            |                    |                  |
--   Dashboard query, result cache    |                    |                  |
--   ride_ref lookup, before          |                    |                  |
--   ride_ref lookup, after           |                    |                  |
--
-- Hint: Query Profile, Section 4.



-- =============================================================================
-- Cleanup (optional, run this when you are done to remove what the lab created).
-- Remove search optimization first, so it stops costing you.
-- =============================================================================
-- ALTER TABLE ride_lookup DROP SEARCH OPTIMIZATION;
-- DROP DATABASE IF EXISTS TRIPLEDGER;
-- DROP WAREHOUSE IF EXISTS TRIP_PERF_WH;
