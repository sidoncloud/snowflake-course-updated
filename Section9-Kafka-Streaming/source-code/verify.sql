-- =============================================================================
-- LAB - Stream Events End to End: verify the landed records
-- Section 9: Real-Time Streaming with Kafka
-- Run in a Snowsight worksheet as ACCOUNTADMIN after producing events.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
USE SCHEMA KAFKA_LAB.KAFKA;

-- 1. The connector landed rows on its own. Five events, five rows.
SELECT COUNT(*) AS row_count FROM PRODUCT_EVENTS;

-- 2. Look at the two raw VARIANT columns the connector writes.
SELECT RECORD_METADATA, RECORD_CONTENT
FROM PRODUCT_EVENTS
LIMIT 5;

-- 3. RECORD_CONTENT is a parsed object (not a string), because the connector
--    used JsonConverter with schemas.enable = false. So dot notation works.
SELECT TYPEOF(RECORD_CONTENT) AS content_type FROM PRODUCT_EVENTS LIMIT 1;

-- 4. Shape the events into columns with dot notation and casts.
SELECT
    RECORD_CONTENT:event_id::INT        AS event_id,
    RECORD_CONTENT:product::STRING      AS product,
    RECORD_CONTENT:qty::INT             AS qty,
    RECORD_CONTENT:price::NUMBER(10,2)  AS price,
    RECORD_METADATA:topic::STRING       AS topic,
    RECORD_METADATA:partition::INT      AS partition,
    RECORD_METADATA:offset::INT         AS kafka_offset
FROM PRODUCT_EVENTS
ORDER BY kafka_offset;

-- 5. Produce more events from the shell and re-run step 1. The count climbs
--    within seconds, with no COPY INTO and no command from you.
