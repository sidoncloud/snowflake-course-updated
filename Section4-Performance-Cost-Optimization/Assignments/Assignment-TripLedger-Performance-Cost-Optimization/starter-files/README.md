# TripLedger: Performance and Cost Optimization Assignment (Starter Kit)

## The scenario

TripLedger is a ride-hailing analytics platform, and its finance team runs monthly reports over the full trip history. Those reports are slow and expensive because they read far more data than they need. The support team also looks up single trips by a random reference number, and on twenty million rows that lookup scans everything. Your job is to fix the layout, the caching and the lookups, and prove every fix with real numbers.

## The data you get

Nothing to upload. `starter.sql` builds it all.

- `trips`: 1,500,000 trips copied from Snowflake's free `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS` sample (trip_id, rider_id, trip_date, fare_usd, priority).
- `ride_lookup`: 20,000,000 rows with a random `ride_ref` and a text payload, generated in Task 4.

## Your tasks

1. Measure how well the trips table is laid out for date-range reports
2. Fix the layout so a monthly report reads only what it needs
3. Show the difference between the warehouse cache and the result cache
4. Make the single-trip lookup fast on twenty million rows
5. Find out what each warehouse actually cost
6. Prove every fix with numbers from Query Profile

## Prerequisites

- A Snowflake trial account with the ACCOUNTADMIN role. Search optimization needs Enterprise edition, which is what a trial gives you by default.
- The `SNOWFLAKE_SAMPLE_DATA` database, which every account has. If you can't see it, ask your admin or recreate it from the Snowflake docs.

## How to start

1. Open a new SQL worksheet in Snowsight and paste in `starter.sql`.
2. Run the SETUP block. It creates `TRIP_PERF_WH`, the `TRIPLEDGER.PERF` schema, and the `trips` table.
3. Work through the tasks in order. Each task gives you the slow query to fix. Task 4 starts by generating the 20 million row table, which takes a little while.
4. Keep the Query Profile open as you go, because Task 6 asks for the numbers.

## Files

- `starter.sql`: setup, the given queries, and one TODO section per task.

Full solution with a step-by-step walkthrough and source code: https://cognifydata.com/labs/snowflake-performance-cost-optimization (free, no sign-up).
