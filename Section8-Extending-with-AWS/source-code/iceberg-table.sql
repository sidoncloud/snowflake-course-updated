-- =============================================================================
-- LAB - Iceberg Table on an S3 External Volume
-- Section 8: Extending Snowflake with AWS Services
-- This lab mixes the AWS console and Snowsight. The console steps are in the
-- comments; run the SQL statements in a Snowsight worksheet as ACCOUNTADMIN.
-- Replace <your-bucket> and <your-account-id> with your own values.
-- =============================================================================

-- REGION: create the S3 bucket, IAM role and external volume in AWS us-east-1; keep it consistent below.

-- ---- In the AWS console, first ----
-- 1. Use an S3 bucket in us-east-1, and pick a prefix for Iceberg, e.g. iceberg/.
-- 2. Create an IAM policy that Snowflake can use to READ and WRITE the files,
--    because a managed Iceberg table writes Parquet and metadata back to S3:
--      On the objects (arn .../*): s3:GetObject, s3:GetObjectVersion,
--        s3:PutObject, s3:DeleteObject.
--      On the bucket itself: s3:ListBucket, s3:GetBucketLocation.
-- 3. Create an IAM role that trusts your own account for now, attach that policy,
--    and copy the role ARN. We fix the trust in step 3 below.

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS ICEBERG_LAB;
CREATE SCHEMA   IF NOT EXISTS ICEBERG_LAB.LAKEHOUSE;
USE SCHEMA ICEBERG_LAB.LAKEHOUSE;

-- ---- In Snowsight ----

-- 1. Create the external volume. It points Snowflake at the bucket and prefix,
--    through the role it will assume. ALLOW_WRITES defaults to TRUE.
CREATE OR REPLACE EXTERNAL VOLUME ice_vol
  STORAGE_LOCATIONS = (
    (
      NAME = 'us-east-1-s3'
      STORAGE_PROVIDER = 'S3'
      STORAGE_BASE_URL = 's3://<your-bucket>/iceberg/'
      STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<your-account-id>:role/snowflake-iceberg-role'
    )
  );

-- 2. Read back the identity Snowflake generated for the volume. You need both.
DESC EXTERNAL VOLUME ice_vol;
--    In the STORAGE_LOCATION_1 JSON, note STORAGE_AWS_IAM_USER_ARN and
--    STORAGE_AWS_EXTERNAL_ID. These drive the trust, exactly like a storage
--    integration did.

-- ---- Back in the AWS console: fix the role's trust (the step everyone forgets) ----
-- 3. Edit the role's trust policy. Set the Principal to the
--    STORAGE_AWS_IAM_USER_ARN, and add a Condition requiring sts:ExternalId to
--    equal the STORAGE_AWS_EXTERNAL_ID. Save it. Without this you get Access Denied.

-- ---- Back in Snowsight ----

-- 4. Verify the whole trust dance before you build anything on top of it.
SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('ice_vol');
--    Read the JSON: writeResult, readResult, listResult, deleteResult should all
--    say PASSED. If any FAIL, the trust or the policy is wrong.

-- 5. Create a Snowflake-managed Iceberg table. CATALOG = 'SNOWFLAKE' means
--    Snowflake owns the metadata and you get full read and write. BASE_LOCATION
--    is the subfolder under the volume's prefix where this table's files live.
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

-- 6. Load and query it exactly like a normal table. The rows are written to S3 as
--    Parquet, with Iceberg metadata alongside.
INSERT INTO orders_iceberg VALUES
  (1,'Ava','Keyboard',49.99,'2026-01-05 10:00:00'),
  (2,'Liam','Monitor',219.00,'2026-01-05 11:30:00'),
  (3,'Mia','Mouse',19.50,'2026-01-06 09:15:00'),
  (4,'Noah','Laptop',1299.00,'2026-01-06 14:45:00'),
  (5,'Emma','Webcam',89.00,'2026-01-07 08:20:00');

SELECT COUNT(*) AS row_count, SUM(amount) AS total_amount FROM orders_iceberg;
SELECT customer, product, amount FROM orders_iceberg ORDER BY amount DESC;

-- 7. Because Snowflake is the catalog, updates work too. This rewrites the
--    affected files and advances the Iceberg snapshot.
UPDATE orders_iceberg SET amount = 999.00 WHERE order_id = 4;
SELECT order_id, customer, amount FROM orders_iceberg WHERE order_id = 4;

-- 8. Confirm Snowflake tracks this as an Iceberg table, not a native one.
SELECT TABLE_NAME, IS_ICEBERG
FROM ICEBERG_LAB.INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME = 'ORDERS_ICEBERG';
--    IS_ICEBERG = YES. In S3, look under iceberg/ to see the data/ Parquet files
--    and the metadata/ folder with .metadata.json, manifest .avro, and snapshots.

-- ---- Cleanup (optional, run this when you are done to remove what the lab created) ----
-- DROP ICEBERG TABLE IF EXISTS orders_iceberg;
-- DROP EXTERNAL VOLUME IF EXISTS ice_vol;
-- Then delete the iceberg/ objects from the bucket if you want the files gone too.
