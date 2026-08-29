-- =============================================================================
-- LAB - Stages, file formats, and COPY INTO (CSV / JSON / Parquet)
-- Section 5: Data Loading & Ingestion from AWS S3
-- PREREQ 1: run the storage-integration lab first (it builds s3_int and s3_stage).
-- PREREQ 2: upload the sample files from the datasets/ folder to your bucket:
--   orders.csv -> raw/csv/ , events.json -> raw/json/ , orders.parquet -> raw/parquet/
-- Run in a Snowsight worksheet as ACCOUNTADMIN.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
USE SCHEMA LOADING_LAB.LOAD;

-- 1. A file format describes how to read a file. One per file type.
CREATE OR REPLACE FILE FORMAT ff_csv
  TYPE = CSV  FIELD_OPTIONALLY_ENCLOSED_BY = '"'  SKIP_HEADER = 1;
CREATE OR REPLACE FILE FORMAT ff_json    TYPE = JSON;
CREATE OR REPLACE FILE FORMAT ff_parquet TYPE = PARQUET;

-- 2. CSV. Create the target table, then COPY INTO it from the csv/ prefix.
--    The result row shows the file, status LOADED, and rows_parsed/rows_loaded.
CREATE OR REPLACE TABLE orders_csv (
    order_id INT, customer_name STRING, country STRING,
    order_ts TIMESTAMP_NTZ, status STRING, amount NUMBER(10,2));
COPY INTO orders_csv FROM @s3_stage/csv/ FILE_FORMAT = ff_csv;
SELECT * FROM orders_csv;

-- 3. JSON. A whole JSON document loads into one VARIANT column. Then you reach
--    inside it with the colon and the dot, exactly like the semi-structured lab.
CREATE OR REPLACE TABLE events_json (v VARIANT);
COPY INTO events_json FROM @s3_stage/json/ FILE_FORMAT = ff_json;
SELECT v:order_id::INT AS order_id, v:customer.name::STRING AS customer_name
FROM events_json ORDER BY order_id;

-- 4. Parquet. Parquet carries its own column names, so MATCH_BY_COLUMN_NAME maps
--    them to your table columns instead of matching by position.
CREATE OR REPLACE TABLE orders_parquet (
    order_id INT, customer_name STRING, country STRING, amount NUMBER(10,2));
COPY INTO orders_parquet FROM @s3_stage/parquet/
  FILE_FORMAT = ff_parquet  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;
SELECT * FROM orders_parquet;

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP TABLE IF EXISTS orders_csv;
-- DROP TABLE IF EXISTS events_json;
-- DROP TABLE IF EXISTS orders_parquet;
