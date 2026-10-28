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
--     1. Run the setup lines and STEP 1 below to check your Snowflake region.
--        AWS_EU_WEST_1 = eu-west-1, AWS_US_EAST_1 = us-east-1, and so on.
--   AWS console, S3
--     2. Switch the console region (top right) to the region from step 1.
--        S3 > Create bucket > name it (must be unique, e.g. <yourname>-capstone)
--        > Create bucket. Or use a bucket you already have in that region.
--        Open the bucket > Create folder "capstone" > open it > Create folder
--        "tickets" > open it > Upload > Add files > support_tickets.json > Upload.
--   AWS console, IAM
--     3. IAM > Roles > Create role. Trusted entity type: AWS account, keep
--        "This account" (a placeholder, replaced in step 6). Next > Next (skip
--        permissions) > Role name: snowflake-capstone-role > Create role.
--     4. Open snowflake-capstone-role > Add permissions > Create inline policy
--        > JSON. Delete what is there, paste capstone-s3-policy.json and replace
--        <your-bucket> (3 places). Next > Policy name: snowflake-capstone-access
--        > Create policy. On the role summary, copy the role ARN.
--   Snowsight
--     5. Run STEP 5 below: paste the role ARN and your bucket, create the
--        integration, then run DESC INTEGRATION. Copy the property_value of
--        STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID.
--   AWS console, IAM
--     6. Open snowflake-capstone-role > Trust relationships > Edit trust policy.
--        Delete everything, paste capstone-trust-policy.json and replace
--        <STORAGE_AWS_IAM_USER_ARN> and <STORAGE_AWS_EXTERNAL_ID> with the two
--        values from step 5 > Update policy.
--   Snowsight
--     7. Run STEP 7 to STEP 11 below (file format, stage and LIST, table, load,
--        check). If LIST says Access Denied, check the two values in the trust
--        policy (step 6) and the bucket name in the inline policy (step 4).
--        Do not change STEP 5 to CREATE OR REPLACE: that gives the integration
--        a new external ID and you would have to redo step 6.
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
