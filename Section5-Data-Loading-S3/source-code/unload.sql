-- =============================================================================
-- LAB - Unload (extract) data from Snowflake back to S3
-- Section 5: Data Loading & Ingestion from AWS S3
-- PREREQ: run the storage-integration and copy-into labs first.
-- Run in a Snowsight worksheet as ACCOUNTADMIN. Replace <your-bucket>.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
USE SCHEMA LOADING_LAB.LOAD;

-- 1. A stage that points at an unload/ prefix to write results into.
CREATE OR REPLACE STAGE unload_stage
  STORAGE_INTEGRATION = s3_int
  URL = 's3://<your-bucket>/unload/';

-- 2. COPY INTO a stage (instead of a table) writes the query result out to S3.
--    HEADER = TRUE is a COPY option, not a file-format option. The result row
--    reports rows_unloaded, input_bytes, and output_bytes.
COPY INTO @unload_stage/orders_export
  FROM orders_csv
  FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = GZIP)
  HEADER = TRUE
  OVERWRITE = TRUE;

-- 3. Confirm the file landed in S3. LIST shows the gzipped object Snowflake wrote.
LIST @unload_stage;

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- REMOVE @unload_stage;
-- DROP STAGE IF EXISTS unload_stage;
