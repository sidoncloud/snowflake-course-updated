-- =============================================================================
-- LAB - Change Data Capture with Streams
-- Section 6: Building Pipelines: Streams, Tasks & Dynamic Tables
-- Run in a Snowsight worksheet as ACCOUNTADMIN.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS PIPELINES_LAB;
CREATE SCHEMA   IF NOT EXISTS PIPELINES_LAB.PIPELINES;
USE SCHEMA PIPELINES_LAB.PIPELINES;

-- 1. A base table, with a few rows already in it.
CREATE OR REPLACE TABLE raw_orders (order_id INT, customer STRING, amount NUMBER(10,2), status STRING);
INSERT INTO raw_orders VALUES (1,'Ava',100,'NEW'),(2,'Liam',200,'NEW'),(3,'Mia',300,'NEW');

-- 2. A stream on the table. It starts empty and records every change from now on.
CREATE OR REPLACE STREAM raw_orders_stream ON TABLE raw_orders;
SELECT SYSTEM$STREAM_HAS_DATA('raw_orders_stream');   -- FALSE, nothing changed yet

-- 3. Make three kinds of change: an insert, an update, and a delete.
INSERT INTO raw_orders VALUES (4,'Noah',400,'NEW');
UPDATE raw_orders SET status='SHIPPED' WHERE order_id=1;
DELETE FROM raw_orders WHERE order_id=2;

-- 4. Read the stream and look at the three CDC metadata columns.
SELECT SYSTEM$STREAM_HAS_DATA('raw_orders_stream');   -- TRUE now
SELECT order_id, status, METADATA$ACTION, METADATA$ISUPDATE, METADATA$ROW_ID
FROM raw_orders_stream ORDER BY order_id;
--   An UPDATE shows as a DELETE (old row) + INSERT (new row), both ISUPDATE=TRUE.
--   A pure INSERT is INSERT / FALSE.  A pure DELETE is DELETE / FALSE.

-- 5. Consume the stream. Reading it inside a DML advances its offset and empties it.
CREATE OR REPLACE TABLE orders_history (
    order_id INT, customer STRING, amount NUMBER(10,2), status STRING,
    change_type STRING, changed_at TIMESTAMP_NTZ);
INSERT INTO orders_history
SELECT order_id, customer, amount, status,
       CASE WHEN METADATA$ACTION='INSERT' AND METADATA$ISUPDATE THEN 'UPDATE'
            WHEN METADATA$ACTION='INSERT' THEN 'INSERT' ELSE 'DELETE' END,
       CURRENT_TIMESTAMP()
FROM raw_orders_stream;

SELECT SYSTEM$STREAM_HAS_DATA('raw_orders_stream');   -- FALSE again, stream drained
SELECT * FROM orders_history ORDER BY order_id;
