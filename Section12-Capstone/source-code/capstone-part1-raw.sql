-- =============================================================================
-- CAPSTONE, Part 1: S3 to the Raw Layer
-- Section 12: End-to-End Pipeline on AWS
-- Scenario: an online store receives customer support tickets as JSON files that
-- land in S3. In this part we connect Snowflake to S3 and load the tickets into
-- a raw table.
--
-- Files in this folder:
--   support_tickets.json        the 12 sample tickets, one JSON object per line
--   capstone-s3-policy.json     inline policy that lets the IAM role read the bucket
--   capstone-trust-policy.json  trust policy that lets Snowflake assume the role
--   capstone-part1-raw.sql      this file, the Snowsight part
--
-- This part creates its own storage integration, capstone_s3_int, so it does not
-- depend on anything from earlier sections.
-- Replace <your-bucket> and <your-account-id> with your own values.
--
-- ORDER OF STEPS
--   Snowsight
--     1. Run STEP 1 below to check your Snowflake region.
--   AWS console
--     2. S3: create a bucket in that region (or use one you have). Create the
--        folders capstone/tickets/ and upload support_tickets.json into it.
--     3. IAM: create role snowflake-capstone-role, trusted entity = AWS account,
--        This account (a placeholder, replaced in step 6).
--     4. IAM: on that role, Add permissions > Create inline policy > JSON,
--        paste capstone-s3-policy.json, replace <your-bucket>. Copy the role ARN.
--   Snowsight
--     5. Run STEP 5 below (storage integration), then DESC INTEGRATION and copy
--        STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID.
--   AWS console
--     6. IAM: on the role, Trust relationships > Edit trust policy,
--        paste capstone-trust-policy.json with the two values from step 5.
--   Snowsight
--     7. Run STEP 7 to STEP 11 below (file format, stage, list, table, load, check).
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;

CREATE DATABASE IF NOT EXISTS CAPSTONE_LAB;
CREATE SCHEMA   IF NOT EXISTS CAPSTONE_LAB.CAPSTONE;
USE SCHEMA CAPSTONE_LAB.CAPSTONE;

-- -----------------------------------------------------------------------------
-- STEP 1: your Snowflake region. Create the S3 bucket in the same AWS region.
--   AWS_US_EAST_1 = us-east-1, AWS_EU_WEST_1 = eu-west-1, and so on.
-- -----------------------------------------------------------------------------
SELECT CURRENT_REGION();

-- -----------------------------------------------------------------------------
-- STEP 5: the storage integration. Paste the role ARN from step 4 and your bucket.
--   IF NOT EXISTS: if you run this again, the integration keeps its external ID,
--   so the trust policy from step 6 keeps working.
-- -----------------------------------------------------------------------------
CREATE STORAGE INTEGRATION IF NOT EXISTS capstone_s3_int
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<your-account-id>:role/snowflake-capstone-role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://<your-bucket>/capstone/');

-- Copy STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID from the result.
-- They go into capstone-trust-policy.json in step 6.
DESC INTEGRATION capstone_s3_int;

-- -----------------------------------------------------------------------------
-- STEP 7: a JSON file format. Each line in the file is one ticket object.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FILE FORMAT ff_json
  TYPE = JSON
  STRIP_OUTER_ARRAY = FALSE;

-- -----------------------------------------------------------------------------
-- STEP 8: an external stage on the integration, pointed at the tickets folder.
--   Then LIST it. You should see support_tickets.json. If you get Access Denied,
--   check the trust policy from step 6 and the bucket name in the inline policy.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE STAGE tickets_stage
  STORAGE_INTEGRATION = capstone_s3_int
  URL = 's3://<your-bucket>/capstone/tickets/'
  FILE_FORMAT = ff_json;

LIST @tickets_stage;

-- -----------------------------------------------------------------------------
-- STEP 9: the raw table. We keep the whole ticket as a VARIANT and record which
--   file it came from and when, so the raw layer keeps the data as it arrived.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE raw_tickets (
  raw         VARIANT,
  source_file STRING,
  load_ts     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- -----------------------------------------------------------------------------
-- STEP 10: load it. We select the file column and the filename, so every row
--   records its source. In production you would put a Snowpipe on this stage so
--   new files load automatically; here we run the COPY once.
-- -----------------------------------------------------------------------------
COPY INTO raw_tickets (raw, source_file)
  FROM (SELECT $1, METADATA$FILENAME FROM @tickets_stage)
  FILE_FORMAT = (FORMAT_NAME = ff_json)
  ON_ERROR = ABORT_STATEMENT;

-- -----------------------------------------------------------------------------
-- STEP 11: check the raw layer. 12 rows, then the fields read with dot notation.
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS raw_row_count FROM raw_tickets;

SELECT
  raw:ticket_id::int         AS ticket_id,
  raw:customer_email::string AS customer_email,
  raw:product::string        AS product,
  raw:region::string         AS region
FROM raw_tickets
ORDER BY ticket_id;

-- The raw layer is ready. Part 2 transforms, enriches, and serves it.
