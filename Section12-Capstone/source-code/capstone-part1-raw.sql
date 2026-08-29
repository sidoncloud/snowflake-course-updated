-- =============================================================================
-- CAPSTONE, Part 1: S3 to the Raw Layer
-- Section 12: End-to-End Pipeline on AWS
-- Scenario: an online store receives customer support tickets as JSON files that
-- land in S3. In this part we connect to S3 and load the tickets into a raw table.
-- Run in a Snowsight worksheet as ACCOUNTADMIN.
-- REGION: your S3 bucket and the Section 5 s3_int storage integration must be in AWS us-east-1; keep it consistent below.
-- Prereq: the s3_int storage integration from Section 5 (its IAM trust is set up).
-- Replace <your-bucket> with your own bucket, and upload support_tickets.json
-- (in this folder) to the capstone/tickets/ prefix first.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;

CREATE DATABASE IF NOT EXISTS CAPSTONE_LAB;
CREATE SCHEMA   IF NOT EXISTS CAPSTONE_LAB.CAPSTONE;
USE SCHEMA CAPSTONE_LAB.CAPSTONE;

-- 1. A JSON file format. Each line in the file is one ticket object.
CREATE OR REPLACE FILE FORMAT ff_json
  TYPE = JSON
  STRIP_OUTER_ARRAY = FALSE;

-- 2. An external stage on the storage integration, pointed at the tickets prefix.
CREATE OR REPLACE STAGE tickets_stage
  STORAGE_INTEGRATION = s3_int
  URL = 's3://<your-bucket>/capstone/tickets/'
  FILE_FORMAT = ff_json;

-- 3. Confirm Snowflake can see the file through the stage. If you get Access
--    Denied here, revisit the IAM trust policy from the Section 5 storage lab.
LIST @tickets_stage;

-- 4. The raw landing table. We keep the whole ticket as a VARIANT and record
--    which file and when, so the raw layer stays faithful to what arrived.
CREATE OR REPLACE TABLE raw_tickets (
  raw         VARIANT,
  source_file STRING,
  load_ts     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 5. Load it. We select the file column and the filename, so every row remembers
--    its source. In production you would put a Snowpipe on this stage so new files
--    load automatically; here we run the COPY once.
COPY INTO raw_tickets (raw, source_file)
  FROM (SELECT $1, METADATA$FILENAME FROM @tickets_stage)
  FILE_FORMAT = (FORMAT_NAME = ff_json)
  ON_ERROR = ABORT_STATEMENT;

-- 6. Prove the raw layer landed. You should see one row per ticket in the file.
SELECT COUNT(*) AS raw_row_count FROM raw_tickets;

-- 7. Peek at the semi-structured data with dot notation before we move on.
SELECT
  raw:ticket_id::int        AS ticket_id,
  raw:customer_email::string AS customer_email,
  raw:product::string       AS product,
  raw:region::string        AS region
FROM raw_tickets
ORDER BY ticket_id;

-- The raw layer is ready. Part 2 transforms, enriches, and serves it.
