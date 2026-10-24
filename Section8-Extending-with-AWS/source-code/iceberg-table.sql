-- =============================================================================
-- LAB - Iceberg Table on an S3 External Volume
-- Section 8: Extending Snowflake with AWS Services
--
-- Files in this folder:
--   iceberg-s3-policy.json     inline policy that lets the IAM role read and write the bucket
--   iceberg-trust-policy.json  trust policy that lets Snowflake assume the role
--   iceberg-table.sql          this file, the Snowsight part
--
-- Put the S3 bucket in the same AWS region as your Snowflake account.
-- Run STEP 1 below to see your account's region.
-- Replace <your-bucket> and <your-account-id> with your own values.
--
-- ORDER OF STEPS
--   Snowsight
--     1. Run STEP 1 below to check your Snowflake region.
--   AWS console
--     2. S3: create a bucket in that region (or use one you have). The lab writes
--        under the iceberg/ prefix in it.
--     3. IAM: create role snowflake-iceberg-role, trusted entity = AWS account,
--        This account (a placeholder, replaced in step 6).
--     4. IAM: on that role, Add permissions > Create inline policy > JSON,
--        paste iceberg-s3-policy.json, replace <your-bucket>. Copy the role ARN.
--   Snowsight
--     5. Run STEP 5 below (external volume), then DESC EXTERNAL VOLUME and copy
--        STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID.
--   AWS console
--     6. IAM: on the role, Trust relationships > Edit trust policy,
--        paste iceberg-trust-policy.json with the two values from step 5.
--   Snowsight
--     7. Run STEP 7 to STEP 11 below (verify, create the table, load, update, check).
--   AWS console
--     12. S3: open the bucket and browse iceberg/orders_iceberg/ to see the files.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;

CREATE DATABASE IF NOT EXISTS ICEBERG_LAB;
CREATE SCHEMA   IF NOT EXISTS ICEBERG_LAB.LAKEHOUSE;
USE SCHEMA ICEBERG_LAB.LAKEHOUSE;

-- -----------------------------------------------------------------------------
-- STEP 1: your Snowflake region. Create the S3 bucket in the same AWS region.
--   AWS_US_EAST_1 = us-east-1, AWS_EU_WEST_1 = eu-west-1, and so on.
-- -----------------------------------------------------------------------------
SELECT CURRENT_REGION();

-- -----------------------------------------------------------------------------
-- STEP 5: the external volume. Paste the role ARN from step 4 and your bucket.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE EXTERNAL VOLUME ice_vol
  STORAGE_LOCATIONS = (
    (
      NAME = 'iceberg-s3'
      STORAGE_PROVIDER = 'S3'
      STORAGE_BASE_URL = 's3://<your-bucket>/iceberg/'
      STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<your-account-id>:role/snowflake-iceberg-role'
    )
  );

-- Copy STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID from the
-- STORAGE_LOCATION_1 row. They go into iceberg-trust-policy.json in step 6.
DESC EXTERNAL VOLUME ice_vol;

-- -----------------------------------------------------------------------------
-- STEP 7: check that Snowflake can use the bucket. Run this after step 6.
--   In the JSON, writeResult, readResult, listResult and deleteResult should
--   all say PASSED.
-- -----------------------------------------------------------------------------
SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('ice_vol');

-- -----------------------------------------------------------------------------
-- STEP 8: a Snowflake-managed Iceberg table.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE ICEBERG TABLE orders_iceberg (
    order_id INT,
    customer STRING,
    product  STRING,
    amount   NUMBER(10,2),
    order_ts TIMESTAMP_NTZ
)
  CATALOG = 'SNOWFLAKE'
  EXTERNAL_VOLUME = 'ice_vol'
  BASE_LOCATION = 'orders_iceberg';

-- -----------------------------------------------------------------------------
-- STEP 9: load and query it.
-- -----------------------------------------------------------------------------
INSERT INTO orders_iceberg VALUES
  (1,'Ava','Keyboard',49.99,'2026-01-05 10:00:00'),
  (2,'Liam','Monitor',219.00,'2026-01-05 11:30:00'),
  (3,'Mia','Mouse',19.50,'2026-01-06 09:15:00'),
  (4,'Noah','Laptop',1299.00,'2026-01-06 14:45:00'),
  (5,'Emma','Webcam',89.00,'2026-01-07 08:20:00');

SELECT COUNT(*) AS row_count, SUM(amount) AS total_amount FROM orders_iceberg;
SELECT customer, product, amount FROM orders_iceberg ORDER BY amount DESC;

-- -----------------------------------------------------------------------------
-- STEP 10: update a row.
-- -----------------------------------------------------------------------------
UPDATE orders_iceberg SET amount = 999.00 WHERE order_id = 4;
SELECT order_id, customer, amount FROM orders_iceberg WHERE order_id = 4;

-- -----------------------------------------------------------------------------
-- STEP 11: confirm Snowflake tracks it as an Iceberg table. IS_ICEBERG = YES.
-- -----------------------------------------------------------------------------
SELECT TABLE_NAME, IS_ICEBERG
FROM ICEBERG_LAB.INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME = 'ORDERS_ICEBERG';

-- -----------------------------------------------------------------------------
-- CLEANUP (run when you are done)
-- -----------------------------------------------------------------------------
-- DROP ICEBERG TABLE IF EXISTS orders_iceberg;
-- DROP EXTERNAL VOLUME IF EXISTS ice_vol;
-- DROP DATABASE IF EXISTS ICEBERG_LAB;
-- Then in AWS: delete the iceberg/ folder in the bucket and the snowflake-iceberg-role.
