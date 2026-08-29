-- =============================================================================
-- LAB - Dynamic Tables
-- Section 6: Building Pipelines: Streams, Tasks & Dynamic Tables
-- PREREQ: run the streams lab first (it built raw_orders).
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
USE SCHEMA PIPELINES_LAB.PIPELINES;

-- A dynamic table is declarative. You write the query, set a target lag, and
-- Snowflake keeps the result refreshed for you. No stream, no task, no COPY.
CREATE OR REPLACE DYNAMIC TABLE orders_by_customer
  TARGET_LAG = '1 MINUTE'
  WAREHOUSE  = COURSE_WH
AS
  SELECT customer, COUNT(*) AS order_count, SUM(amount) AS total_amount
  FROM raw_orders GROUP BY customer;

-- It refreshes once when it is created. Read it.
SELECT * FROM orders_by_customer ORDER BY customer;

-- Now change the base table. Within the target lag, the dynamic table refreshes
-- on its own, incrementally, with no command from you.
INSERT INTO raw_orders VALUES (7,'Ava',150,'NEW'),(8,'Ivy',700,'NEW');

-- Re-run after about a minute: Ava's total climbs and Ivy appears.
SELECT * FROM orders_by_customer ORDER BY customer;

-- Inspect the refreshes (state SUCCEEDED, refresh_action INCREMENTAL).
SELECT name, state, refresh_action, data_timestamp
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
WHERE name='ORDERS_BY_CUSTOMER' ORDER BY data_timestamp DESC;

-- Cleanup (optional):
-- DROP DYNAMIC TABLE IF EXISTS orders_by_customer;
