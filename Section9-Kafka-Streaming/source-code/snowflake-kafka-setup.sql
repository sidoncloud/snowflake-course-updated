-- =============================================================================
-- LAB - Configure the Kafka Snowflake Connector: the Snowflake side
-- Section 9: Real-Time Streaming with Kafka
-- Run in a Snowsight worksheet as ACCOUNTADMIN.
--
-- This creates the service user the Kafka connector logs in as, its role and
-- grants, and the target table events will land in. The connector authenticates
-- with an RSA key pair, so run generate-key-pair.sh first and paste the public
-- key body into the CREATE USER statement below.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS KAFKA_LAB;
CREATE SCHEMA   IF NOT EXISTS KAFKA_LAB.KAFKA;
USE SCHEMA KAFKA_LAB.KAFKA;

-- 1. A role for the connector, granted least privilege only.
CREATE OR REPLACE ROLE KAFKA_CONNECTOR_ROLE;

-- 2. A dedicated service user that authenticates with a public key, not a
--    password. Paste the RSA_PUBLIC_KEY value printed by generate-key-pair.sh.
CREATE OR REPLACE USER KAFKA_CONNECTOR_USER
    RSA_PUBLIC_KEY = 'PASTE_YOUR_PUBLIC_KEY_BODY_HERE'
    DEFAULT_ROLE  = KAFKA_CONNECTOR_ROLE
    DEFAULT_WAREHOUSE = COURSE_WH
    COMMENT = 'Service user for the Snowflake Kafka connector';

GRANT ROLE KAFKA_CONNECTOR_ROLE TO USER KAFKA_CONNECTOR_USER;
GRANT ROLE KAFKA_CONNECTOR_ROLE TO ROLE ACCOUNTADMIN;

-- 3. Grants the connector needs. In Snowpipe Streaming mode it manages its own
--    ingestion objects, so it needs CREATE TABLE, STAGE, and PIPE on the schema.
GRANT USAGE ON WAREHOUSE COURSE_WH        TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT USAGE ON DATABASE KAFKA_LAB    TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT USAGE ON SCHEMA KAFKA_LAB.KAFKA TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT CREATE TABLE ON SCHEMA KAFKA_LAB.KAFKA TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT CREATE STAGE ON SCHEMA KAFKA_LAB.KAFKA TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT CREATE PIPE  ON SCHEMA KAFKA_LAB.KAFKA TO ROLE KAFKA_CONNECTOR_ROLE;

-- 4. The target table. The connector writes two VARIANT columns: RECORD_METADATA
--    (topic, partition, offset, timestamp) and RECORD_CONTENT (the message body).
CREATE OR REPLACE TABLE PRODUCT_EVENTS (
    RECORD_METADATA VARIANT,
    RECORD_CONTENT  VARIANT
);
GRANT SELECT, INSERT ON TABLE PRODUCT_EVENTS TO ROLE KAFKA_CONNECTOR_ROLE;

-- 5. Confirm the objects exist.
SHOW USERS LIKE 'KAFKA_CONNECTOR_USER';
DESC TABLE PRODUCT_EVENTS;

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP TABLE IF EXISTS KAFKA_LAB.KAFKA.PRODUCT_EVENTS;
-- DROP USER  IF EXISTS KAFKA_CONNECTOR_USER;
-- DROP ROLE  IF EXISTS KAFKA_CONNECTOR_ROLE;
