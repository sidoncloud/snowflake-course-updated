-- =============================================================================
-- LAB - Storage Integration: connect Snowflake to S3
-- Section 5: Data Loading & Ingestion from AWS S3
-- This lab mixes the AWS console and Snowsight. The console steps are in the
-- comments; run the SQL statements in a Snowsight worksheet as ACCOUNTADMIN.
-- Replace <your-bucket> and <your-account-id> with your own values.
-- =============================================================================

-- REGION: create your S3 bucket, IAM policy and role in AWS us-east-1, and keep that region consistent everywhere below.

-- ---- In the AWS console, first ----
-- 1. Create an S3 bucket in us-east-1, for example snowflake-course-labs-<account>.
--    Upload a sample file under a raw/ prefix so there is something to read.
-- 2. Create an IAM policy: paste s3-access-policy.json (in this folder) into the
--    JSON editor and replace <your-bucket>. It grants read AND write on the
--    objects (GetObject/PutObject/etc, write is needed for the unload lab) plus
--    ListBucket and GetBucketLocation on the bucket.
-- 3. Create an IAM role that trusts your own account for now, and attach that
--    policy. Copy the role ARN. We fix the trust in step 3 below.

USE ROLE ACCOUNTADMIN;

-- ---- In Snowsight ----

-- 1. Create the storage integration, pointing at the role ARN and the bucket.
CREATE OR REPLACE STORAGE INTEGRATION s3_int
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<your-account-id>:role/snowflake-s3-role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://<your-bucket>/');

-- 2. Read back the two values Snowflake generated. You need both for the trust.
DESC INTEGRATION s3_int;
--    Note STORAGE_AWS_IAM_USER_ARN  (a Snowflake-owned IAM user ARN)
--    Note STORAGE_AWS_EXTERNAL_ID   (a unique external id)

-- ---- Back in the AWS console (the step everyone forgets) ----
-- 3. Edit your IAM role's trust policy: paste s3-trust-policy.json (in this
--    folder) and fill in the two values, the STORAGE_AWS_IAM_USER_ARN as the
--    Principal and the STORAGE_AWS_EXTERNAL_ID in the sts:ExternalId condition.
--    Save it. Without this, every later command fails with Access Denied.

-- ---- Back in Snowsight ----

-- 4. Build a database, schema, and a stage on the integration.
CREATE DATABASE IF NOT EXISTS LOADING_LAB;
CREATE SCHEMA   IF NOT EXISTS LOADING_LAB.LOAD;
USE SCHEMA LOADING_LAB.LOAD;

CREATE OR REPLACE STAGE s3_stage
  STORAGE_INTEGRATION = s3_int
  URL = 's3://<your-bucket>/raw/';

-- 5. Prove it works. This lists the files in S3 through the stage. If you see
--    your files, the trust dance is complete and the connection is live.
LIST @s3_stage;
