-- =============================================================================
-- L10 LAB - Create warehouses, set a resource monitor, read consumption
-- Section 2: Architecture & Fundamentals
--
-- OPTIONAL. The lecture does this lab in the Snowsight UI (point and click).
-- This worksheet is the SQL version of the exact same steps, in case you'd
-- rather do it in code. Run top to bottom in a Snowsight worksheet, role ACCOUNTADMIN.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- 1. Create a small, cost-safe warehouse. It starts suspended, parks itself
--    after 60 seconds idle, and wakes automatically on the next query.
CREATE WAREHOUSE IF NOT EXISTS COURSE_WH
  WAREHOUSE_SIZE   = 'XSMALL'
  AUTO_SUSPEND     = 60
  AUTO_RESUME      = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Course warehouse for the Snowflake on AWS labs';

USE WAREHOUSE COURSE_WH;

-- 2. Scaling UP: resize to make a single heavy query faster, then back down.
--    Resizing is instant and takes effect on the next query.
ALTER WAREHOUSE COURSE_WH SET WAREHOUSE_SIZE = 'SMALL';
SHOW WAREHOUSES LIKE 'COURSE_WH';
ALTER WAREHOUSE COURSE_WH SET WAREHOUSE_SIZE = 'XSMALL';

-- 2b. Warehouse TYPES. Snowsight's "Type" dropdown shows four choices. They are
--     all just different compute engines. COURSE_WH is the everyday one: a
--     STANDARD warehouse. Standard comes in two hardware generations, Gen2 (the
--     new, faster default) and Gen1 (the original). Look at the type and
--     generation columns for COURSE_WH.
SHOW WAREHOUSES LIKE 'COURSE_WH';        -- type = STANDARD, generation = 2

-- You can pin a generation with the GENERATION property.
CREATE OR REPLACE WAREHOUSE GEN1_DEMO
  WAREHOUSE_SIZE = 'XSMALL' GENERATION = '1' INITIALLY_SUSPENDED = TRUE;

-- A SNOWPARK-OPTIMIZED warehouse has 16x the memory per node for heavy Snowpark,
-- Python, and machine learning work. Its minimum size is MEDIUM, and it costs more.
CREATE OR REPLACE WAREHOUSE SNOWPARK_DEMO
  WAREHOUSE_SIZE = 'MEDIUM' WAREHOUSE_TYPE = 'SNOWPARK-OPTIMIZED' INITIALLY_SUSPENDED = TRUE;

-- An INTERACTIVE warehouse is built for sub-second, high-concurrency real-time
-- analytics, like live dashboards and data-backed APIs.
CREATE OR REPLACE WAREHOUSE INTERACTIVE_DEMO
  WAREHOUSE_SIZE = 'XSMALL' WAREHOUSE_TYPE = 'INTERACTIVE' INITIALLY_SUSPENDED = TRUE;

-- Compare them. Read the type column (STANDARD / SNOWPARK-OPTIMIZED / INTERACTIVE)
-- and the generation column (2 for COURSE_WH, 1 for GEN1_DEMO).
SHOW WAREHOUSES LIKE '%DEMO';

-- Drop the demos. While suspended they cost nothing, but keep the account tidy.
DROP WAREHOUSE IF EXISTS GEN1_DEMO;
DROP WAREHOUSE IF EXISTS SNOWPARK_DEMO;
DROP WAREHOUSE IF EXISTS INTERACTIVE_DEMO;

-- 3. Create a resource monitor: a hard guardrail on credit spend.
--    Notify at 75%, suspend after running queries finish at 90%,
--    and stop immediately at 100%.
CREATE OR REPLACE RESOURCE MONITOR COURSE_RM
  WITH
    CREDIT_QUOTA   = 5
    FREQUENCY      = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 75  PERCENT DO NOTIFY
    ON 90  PERCENT DO SUSPEND
    ON 100 PERCENT DO SUSPEND_IMMEDIATE;

-- 4. Attach the monitor to our warehouse (warehouse-level cap). A monitor only
--    suspends warehouses, it does not stop serverless features.
ALTER WAREHOUSE COURSE_WH SET RESOURCE_MONITOR = COURSE_RM;
SHOW RESOURCE MONITORS;

-- 5. Generate a little work so there is something to measure.
USE WAREHOUSE COURSE_WH;
SELECT COUNT(*) AS sample_rows
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

-- 6. Read consumption the LOW-LATENCY way (current account, near real time):
--    the INFORMATION_SCHEMA table function. IMPORTANT: INFORMATION_SCHEMA is
--    per-database, so you must have a database in context first or it errors
--    with "Invalid identifier". We point at the sample database that always
--    exists. The metering data it returns is still account-wide.
USE DATABASE SNOWFLAKE_SAMPLE_DATA;
SELECT *
FROM TABLE(INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
        DATE_RANGE_START => DATEADD('day', -1, CURRENT_DATE())))
ORDER BY START_TIME DESC;

-- 7. Read consumption the PRECISE way: ACCOUNT_USAGE (note: this view can lag
--    by up to a few hours, so on a brand-new account it may be nearly empty.
--    It is the account-wide historical source of truth over time).
SELECT WAREHOUSE_NAME, START_TIME, CREDITS_USED
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
ORDER BY START_TIME DESC
LIMIT 20;

-- 8. See what actually ran (query history for the current account/session).
SELECT QUERY_TEXT, WAREHOUSE_NAME, EXECUTION_STATUS, TOTAL_ELAPSED_TIME
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
ORDER BY START_TIME DESC
LIMIT 10;

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- ALTER WAREHOUSE COURSE_WH UNSET RESOURCE_MONITOR;
-- DROP RESOURCE MONITOR IF EXISTS COURSE_RM;
-- DROP WAREHOUSE IF EXISTS COURSE_WH;
