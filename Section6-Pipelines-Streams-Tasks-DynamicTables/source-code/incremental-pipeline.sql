-- =============================================================================
-- PROJECT - End-to-End Incremental Pipeline
-- Section 6: Building Pipelines: Streams, Tasks & Dynamic Tables
-- Flow:  raw landing -> stream -> task -> clean layer -> dynamic table -> analytics
-- Run in a Snowsight worksheet as ACCOUNTADMIN.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS PIPELINE_PROJECT_LAB;
CREATE SCHEMA IF NOT EXISTS PIPELINE_PROJECT_LAB.PIPELINE_PROJECT;
USE SCHEMA PIPELINE_PROJECT_LAB.PIPELINE_PROJECT;

-- 1. LANDING - where new orders arrive (from a bulk load, Snowpipe, streaming...).
CREATE OR REPLACE TABLE raw_orders (
    order_id INT, customer STRING, amount NUMBER(10,2), status STRING, event_ts TIMESTAMP_NTZ);

-- 2. STREAM - captures every newly landed row for incremental processing.
CREATE OR REPLACE STREAM raw_orders_stream ON TABLE raw_orders;

-- 3. CLEAN layer + a TASK that incrementally loads only the new rows, normalized.
CREATE OR REPLACE TABLE orders_clean (
    order_id INT, customer STRING, amount NUMBER(10,2), status STRING, event_ts TIMESTAMP_NTZ);
CREATE OR REPLACE TASK load_clean_task
  WAREHOUSE = COURSE_WH
  SCHEDULE  = '1 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('raw_orders_stream')
AS
  INSERT INTO orders_clean
  SELECT order_id, customer, amount, UPPER(status), event_ts
  FROM raw_orders_stream
  WHERE METADATA$ACTION='INSERT';

-- 4. ANALYTICS - a dynamic table on the clean layer, always fresh within its lag.
CREATE OR REPLACE DYNAMIC TABLE revenue_by_customer
  TARGET_LAG = '1 MINUTE'
  WAREHOUSE  = COURSE_WH
AS
  SELECT customer, COUNT(*) AS orders, SUM(amount) AS revenue
  FROM orders_clean GROUP BY customer;

-- 5. RUN IT - land a batch, fire the task, let the dynamic table catch up.
ALTER TASK load_clean_task RESUME;
INSERT INTO raw_orders VALUES
  (1,'Ava',100,'new',CURRENT_TIMESTAMP()),
  (2,'Liam',200,'new',CURRENT_TIMESTAMP()),
  (3,'Ava',50,'new',CURRENT_TIMESTAMP());
EXECUTE TASK load_clean_task;

-- After a few seconds the clean layer is loaded:
SELECT * FROM orders_clean ORDER BY order_id;
-- After about a minute the analytics layer reflects it (Ava 2 orders / 150):
SELECT * FROM revenue_by_customer ORDER BY customer;

-- Suspend the task when you are done.
ALTER TASK load_clean_task SUSPEND;
