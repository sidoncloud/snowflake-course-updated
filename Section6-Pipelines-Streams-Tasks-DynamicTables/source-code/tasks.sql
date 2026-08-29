-- =============================================================================
-- LAB - Tasks and Task Graphs, driven by a Stream
-- Section 6: Building Pipelines: Streams, Tasks & Dynamic Tables
-- PREREQ: run the streams lab first (it built raw_orders and orders_history).
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
USE SCHEMA PIPELINES_LAB.PIPELINES;

-- Refresh the stream and add changes, so there is something to process.
CREATE OR REPLACE STREAM raw_orders_stream ON TABLE raw_orders;
INSERT INTO raw_orders VALUES (5,'Zoe',500,'NEW'),(6,'Kai',600,'NEW');
CREATE OR REPLACE TABLE orders_summary (customer STRING, total_amount NUMBER(12,2));

-- ROOT task: consume the stream into history, but ONLY when the stream has data.
-- The WHEN clause means a scheduled run that finds nothing simply skips, for free.
CREATE OR REPLACE TASK consume_stream_task
  WAREHOUSE = COURSE_WH
  SCHEDULE  = '1 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('raw_orders_stream')
AS
  INSERT INTO orders_history
  SELECT order_id, customer, amount, status,
         CASE WHEN METADATA$ACTION='INSERT' AND METADATA$ISUPDATE THEN 'UPDATE'
              WHEN METADATA$ACTION='INSERT' THEN 'INSERT' ELSE 'DELETE' END,
         CURRENT_TIMESTAMP()
  FROM raw_orders_stream;

-- CHILD task: runs AFTER the root finishes, and rebuilds the summary.
CREATE OR REPLACE TASK refresh_summary_task
  WAREHOUSE = COURSE_WH
  AFTER consume_stream_task
AS
  INSERT OVERWRITE INTO orders_summary
  SELECT customer, SUM(amount) FROM orders_history GROUP BY customer;

-- Resume the child before the root, then the graph is live on its schedule.
ALTER TASK refresh_summary_task RESUME;
ALTER TASK consume_stream_task  RESUME;

-- Run the whole graph now instead of waiting for the minute to tick.
EXECUTE TASK consume_stream_task;

-- Watch the runs (both reach SUCCEEDED), then read the result.
SELECT name, state, scheduled_time
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
       SCHEDULED_TIME_RANGE_START => DATEADD('minute',-5,CURRENT_TIMESTAMP())))
ORDER BY scheduled_time DESC;
SELECT * FROM orders_summary ORDER BY customer;

-- Suspend the tasks when you are done so the schedule stops consuming credits.
ALTER TASK consume_stream_task  SUSPEND;
ALTER TASK refresh_summary_task SUSPEND;
