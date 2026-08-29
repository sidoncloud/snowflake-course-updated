-- =============================================================================
-- LAB - Snowpipe: auto-ingest files as they land in S3
-- Section 5: Data Loading & Ingestion from AWS S3
-- PREREQ: run the storage-integration lab first (it builds s3_int).
-- This lab mixes Snowsight and the AWS console. Replace <your-bucket>.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
USE SCHEMA LOADING_LAB.LOAD;

-- 1. A stage and a target table for files arriving under a stream/ prefix.
CREATE OR REPLACE STAGE pipe_stage
  STORAGE_INTEGRATION = s3_int
  URL = 's3://<your-bucket>/stream/'
  FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

CREATE OR REPLACE TABLE orders_pipe (
    order_id INT, customer_name STRING, country STRING,
    order_ts TIMESTAMP_NTZ, status STRING, amount NUMBER(10,2));

-- 2. Create the pipe. AUTO_INGEST = TRUE means it loads on an S3 event, not on a
--    schedule. The pipe body is a normal COPY INTO.
CREATE OR REPLACE PIPE orders_pipe_pipe
  AUTO_INGEST = TRUE
AS
  COPY INTO orders_pipe FROM @pipe_stage;

-- 3. Get the SQS queue ARN Snowflake created for this pipe. Read the
--    notification_channel column in the output, you need it in the next step.
SHOW PIPES LIKE 'orders_pipe_pipe';

-- ---- In the AWS console ----
-- 4. Open your S3 bucket, Properties, Event notifications, Create event
--    notification. Set the prefix to stream/, choose the event type
--    s3:ObjectCreated (All object create events), and for the destination pick
--    SQS queue, Enter SQS queue ARN, and paste the notification_channel value.
--    Save it. Now every new file under stream/ pings the pipe.

-- 5. Upload stream_orders.csv (from the datasets/ folder) under the stream/ prefix,
--    from the console or the AWS CLI. Within about a minute Snowpipe loads it on its
--    own. Watch the count grow.
SELECT COUNT(*) FROM orders_pipe;

-- 6. Check the pipe is healthy. executionState should read RUNNING.
SELECT SYSTEM$PIPE_STATUS('orders_pipe_pipe');

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP PIPE  IF EXISTS orders_pipe_pipe;
-- DROP TABLE IF EXISTS orders_pipe;
