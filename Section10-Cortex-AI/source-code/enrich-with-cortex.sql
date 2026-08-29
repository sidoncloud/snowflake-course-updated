-- =============================================================================
-- LAB - Enrich Pipeline Data with Cortex LLM Functions
-- Section 10: Snowflake Cortex: AI on Your Pipelines
-- Run in a Snowsight worksheet as ACCOUNTADMIN.
--
-- Cortex LLM functions run on a Snowflake account with Cortex available in your
-- region. This lab uses AWS us-east-1, where the functions below are supported.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS CORTEX_LAB;
CREATE SCHEMA   IF NOT EXISTS CORTEX_LAB.CORTEX_AI;
USE SCHEMA CORTEX_LAB.CORTEX_AI;

-- 1. Raw text landing in a pipeline: incoming support messages, some non-English.
CREATE OR REPLACE TABLE support_messages (
    message_id   INT,
    customer     STRING,
    channel      STRING,
    received_at  TIMESTAMP_NTZ,
    lang         STRING,
    raw_text     STRING);

INSERT INTO support_messages VALUES
 (101,'Ava Chen','email','2026-07-01 09:14:00','en',
      'My laptop arrived with a cracked screen and support has not replied to two emails. I want a refund.'),
 (102,'Liam Novak','chat','2026-07-01 10:02:00','en',
      'Delivery was quick and the packaging was great, really happy with the whole experience.'),
 (103,'Mia Rossi','email','2026-07-01 11:47:00','es',
      'El pedido llego danado y quiero un reembolso lo antes posible.'),
 (104,'Noah Patel','phone','2026-07-01 12:30:00','en',
      'I was double charged for order 5567, can you reverse one of the payments?'),
 (105,'Emma Li','chat','2026-07-01 13:05:00','en',
      'When will my order ship? I placed it on June 28 and still see no tracking.'),
 (106,'Omar Haddad','email','2026-07-01 14:20:00','en',
      'The blender works fine but the instructions were confusing, it took me a while to figure out the settings.');

SELECT * FROM support_messages ORDER BY message_id;

-- 2. SENTIMENT: a score from -1 (negative) to +1 (positive) for each message.
SELECT message_id,
       SNOWFLAKE.CORTEX.SENTIMENT(raw_text) AS sentiment_score
FROM support_messages
ORDER BY message_id;

-- 3. TRANSLATE: bring the non-English message into English so the rest works on it.
SELECT message_id, lang, raw_text,
       SNOWFLAKE.CORTEX.TRANSLATE(raw_text, 'es', 'en') AS english_text
FROM support_messages
WHERE lang = 'es';

-- 4. CLASSIFY_TEXT: sort each message into one of our support categories.
--    It returns an object; the chosen category is in the :label field.
SELECT message_id,
       SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
           raw_text,
           ['shipping damage','billing issue','delivery delay','product question']
       ):label::STRING AS category
FROM support_messages
ORDER BY message_id;

-- 5. SUMMARIZE: a one-line gist for a long message.
SELECT message_id,
       SNOWFLAKE.CORTEX.SUMMARIZE(raw_text) AS summary
FROM support_messages
WHERE message_id = 101;

-- 6. EXTRACT_ANSWER: pull a specific answer out of the text.
--    It returns an array of {answer, score}; take the first answer.
SELECT message_id,
       SNOWFLAKE.CORTEX.EXTRACT_ANSWER(raw_text, 'What order number is mentioned?')[0]:answer::STRING AS order_ref
FROM support_messages
WHERE message_id = 104;

-- 7. COMPLETE: a custom instruction the task functions do not cover.
--    A small model is plenty for routing, and it is the cheaper choice.
SELECT message_id,
       TRIM(SNOWFLAKE.CORTEX.COMPLETE('llama3.1-8b',
            'Route this support message to one team. Reply with exactly one word from: '
            || 'REFUNDS, BILLING, SHIPPING, PRODUCT_HELP. Message: ' || raw_text)) AS route_to
FROM support_messages
ORDER BY message_id;

-- 8. Put it all together: one enriched, serving-ready table.
CREATE OR REPLACE TABLE support_messages_enriched AS
SELECT
    m.message_id,
    m.customer,
    m.channel,
    m.received_at,
    IFF(m.lang = 'en', m.raw_text,
        SNOWFLAKE.CORTEX.TRANSLATE(m.raw_text, m.lang, 'en'))          AS english_text,
    SNOWFLAKE.CORTEX.SENTIMENT(m.raw_text)                             AS sentiment_score,
    CASE WHEN SNOWFLAKE.CORTEX.SENTIMENT(m.raw_text) >=  0.3 THEN 'POSITIVE'
         WHEN SNOWFLAKE.CORTEX.SENTIMENT(m.raw_text) <= -0.3 THEN 'NEGATIVE'
         ELSE 'NEUTRAL' END                                           AS sentiment_label,
    SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
        m.raw_text,
        ['shipping damage','billing issue','delivery delay','product question']
    ):label::STRING                                                   AS category,
    TRIM(SNOWFLAKE.CORTEX.COMPLETE('llama3.1-8b',
        'Route this support message to one team. Reply with exactly one word from: '
        || 'REFUNDS, BILLING, SHIPPING, PRODUCT_HELP. Message: ' || m.raw_text)) AS route_to
FROM support_messages m;

SELECT message_id, customer, sentiment_score, sentiment_label, category, route_to
FROM support_messages_enriched
ORDER BY message_id;

-- 9. Make the enrichment part of the pipeline: a dynamic table keeps it current.
--    New rows landing in support_messages get scored and routed automatically.
CREATE OR REPLACE DYNAMIC TABLE support_messages_ai
    TARGET_LAG = '1 minute'
    WAREHOUSE  = COURSE_WH
AS
SELECT
    m.message_id,
    m.customer,
    m.channel,
    SNOWFLAKE.CORTEX.SENTIMENT(m.raw_text)                            AS sentiment_score,
    SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
        m.raw_text,
        ['shipping damage','billing issue','delivery delay','product question']
    ):label::STRING                                                   AS category
FROM support_messages m;

SELECT * FROM support_messages_ai ORDER BY message_id;

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP DYNAMIC TABLE IF EXISTS support_messages_ai;
-- DROP TABLE IF EXISTS support_messages_enriched;
-- DROP TABLE IF EXISTS support_messages;
