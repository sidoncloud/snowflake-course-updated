-- =============================================================================
-- LAB - Enrich Pipeline Data with Cortex AI Functions
-- Section 10: Snowflake Cortex, AI on Your Pipelines
-- Run in a Snowsight worksheet as ACCOUNTADMIN.
--
-- This lab uses AI_AGG, AI_SUMMARIZE_AGG and AI_REDACT, which run on trial
-- accounts. AI_AGG is an aggregate function: it answers your instruction over
-- the text in each group. When we GROUP BY the message, every message is its
-- own group, so every message gets its own answer.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS CORTEX_LAB;
CREATE SCHEMA   IF NOT EXISTS CORTEX_LAB.CORTEX_AI;
USE SCHEMA CORTEX_LAB.CORTEX_AI;

-- STEP 1. Raw support messages landing in a pipeline, one of them in Spanish.
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
      'I was double charged for order 5567, can you reverse one of the payments? Call me back on 415-555-0142.'),
 (105,'Emma Li','chat','2026-07-01 13:05:00','en',
      'When will my order ship? I placed it on June 28 and still see no tracking.'),
 (106,'Omar Haddad','email','2026-07-01 14:20:00','en',
      'The blender works fine but the instructions were confusing, it took me a while to figure out the settings.');

SELECT * FROM support_messages ORDER BY message_id;

-- STEP 2. Sentiment: one label per message.
SELECT message_id,
       raw_text,
       AI_AGG(raw_text,
         'Classify the sentiment of this support message. Answer with exactly one word: Negative, Neutral or Positive.'
       ) AS sentiment
FROM support_messages
GROUP BY message_id, raw_text
ORDER BY message_id;

-- STEP 3. Translate the Spanish message into English.
SELECT message_id,
       raw_text,
       AI_AGG(raw_text,
         'Translate this text into English. Return only the translation.'
       ) AS english_text
FROM support_messages
WHERE lang <> 'en'
GROUP BY message_id, raw_text;

-- STEP 4. Classify each message into one of our support categories.
SELECT message_id,
       raw_text,
       AI_AGG(raw_text,
         'Classify this support message into exactly one of these categories: shipping damage, billing issue, delivery delay, product defect, product question, general feedback. Answer with the category name only.'
       ) AS category
FROM support_messages
GROUP BY message_id, raw_text
ORDER BY message_id;

-- STEP 5. Extract one fact from the text: the order number.
SELECT message_id,
       raw_text,
       AI_AGG(raw_text,
         'What order number is mentioned in this message? Answer with the number only, or NONE if there is no order number.'
       ) AS order_ref
FROM support_messages
GROUP BY message_id, raw_text
ORDER BY message_id;

-- STEP 6. Redact personal data before the text goes downstream.
SELECT message_id,
       raw_text,
       AI_REDACT(raw_text)::STRING AS redacted_text
FROM support_messages
ORDER BY message_id;

-- STEP 7. Summarize the whole inbox into one short brief.
SELECT AI_SUMMARIZE_AGG(raw_text) AS inbox_summary
FROM support_messages;

-- STEP 8. Put it all together: one enriched, serving-ready table.
CREATE OR REPLACE TABLE support_messages_enriched AS
SELECT
    m.message_id,
    m.customer,
    m.channel,
    m.received_at,
    IFF(m.lang = 'en', m.raw_text,
        AI_AGG(m.raw_text,
          'Translate this text into English. Return only the translation.'))      AS english_text,
    AI_REDACT(m.raw_text)::STRING                                                 AS redacted_text,
    AI_AGG(m.raw_text,
      'Classify the sentiment of this support message. Answer with exactly one word: Negative, Neutral or Positive.'
    )                                                                             AS sentiment,
    AI_AGG(m.raw_text,
      'Classify this support message into exactly one of these categories: shipping damage, billing issue, delivery delay, product defect, product question, general feedback. Answer with the category name only.'
    )                                                                             AS category
FROM support_messages m
GROUP BY m.message_id, m.customer, m.channel, m.received_at, m.lang, m.raw_text;

SELECT message_id, customer, english_text, redacted_text, sentiment, category
FROM support_messages_enriched
ORDER BY message_id;

-- STEP 9. Make the enrichment part of the pipeline with a dynamic table.
--   AI_AGG is non-deterministic, so Snowflake picks FULL refresh mode: when new rows
--   arrive, the AI functions run on every row again. Suspend it when you are done.
CREATE OR REPLACE DYNAMIC TABLE support_messages_ai
    TARGET_LAG = '1 minute'
    WAREHOUSE  = COURSE_WH
AS
SELECT
    m.message_id,
    m.customer,
    m.channel,
    AI_AGG(m.raw_text,
      'Classify the sentiment of this support message. Answer with exactly one word: Negative, Neutral or Positive.'
    )                                                                             AS sentiment,
    AI_AGG(m.raw_text,
      'Classify this support message into exactly one of these categories: shipping damage, billing issue, delivery delay, product defect, product question, general feedback. Answer with the category name only.'
    )                                                                             AS category
FROM support_messages m
GROUP BY ALL;

SELECT * FROM support_messages_ai ORDER BY message_id;

-- STEP 10. A new message lands. Wait about a minute, then query the dynamic table again.
INSERT INTO support_messages VALUES
 (107,'Sara Kim','chat','2026-07-01 15:10:00','en',
      'The headphones I ordered stopped charging after two days. Can I get a replacement?');

SELECT * FROM support_messages_ai ORDER BY message_id;

SHOW DYNAMIC TABLES LIKE 'SUPPORT_MESSAGES_AI'
  ->> SELECT "name", "target_lag", "refresh_mode", "refresh_mode_reason", "scheduling_state" FROM $1;

-- STEP 11. Suspend the dynamic table so it stops refreshing every minute.
ALTER DYNAMIC TABLE support_messages_ai SUSPEND;

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP DYNAMIC TABLE IF EXISTS support_messages_ai;
-- DROP TABLE IF EXISTS support_messages_enriched;
-- DROP TABLE IF EXISTS support_messages;
-- DROP DATABASE IF EXISTS CORTEX_LAB;
