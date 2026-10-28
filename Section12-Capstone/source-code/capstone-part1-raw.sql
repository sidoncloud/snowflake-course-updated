USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;

CREATE DATABASE IF NOT EXISTS CAPSTONE_LAB;
CREATE SCHEMA   IF NOT EXISTS CAPSTONE_LAB.CAPSTONE;
USE SCHEMA CAPSTONE_LAB.CAPSTONE;

-- STEP 1
SELECT CURRENT_REGION();

-- STEP 5
CREATE STORAGE INTEGRATION IF NOT EXISTS capstone_s3_int
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<your-account-id>:role/snowflake-capstone-role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://<your-bucket>/capstone/');

DESC INTEGRATION capstone_s3_int;

-- STEP 7
CREATE OR REPLACE FILE FORMAT ff_json
  TYPE = JSON
  STRIP_OUTER_ARRAY = FALSE;

-- STEP 8
CREATE OR REPLACE STAGE tickets_stage
  STORAGE_INTEGRATION = capstone_s3_int
  URL = 's3://<your-bucket>/capstone/tickets/'
  FILE_FORMAT = ff_json;

LIST @tickets_stage;

-- STEP 9
CREATE OR REPLACE TABLE raw_tickets (
  raw         VARIANT,
  source_file STRING,
  load_ts     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- STEP 10
COPY INTO raw_tickets (raw, source_file)
  FROM (SELECT $1, METADATA$FILENAME FROM @tickets_stage)
  FILE_FORMAT = (FORMAT_NAME = ff_json)
  ON_ERROR = ABORT_STATEMENT;

-- STEP 11
SELECT COUNT(*) AS raw_row_count FROM raw_tickets;

SELECT
  raw:ticket_id::int         AS ticket_id,
  raw:customer_email::string AS customer_email,
  raw:product::string        AS product,
  raw:region::string         AS region
FROM raw_tickets
ORDER BY ticket_id;
