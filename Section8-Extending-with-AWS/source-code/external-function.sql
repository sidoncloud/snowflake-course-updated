-- =============================================================================
-- LAB - External Functions: calling AWS Lambda from Snowflake
-- Section 8: Extending Snowflake with AWS Services
-- This lab mixes the AWS console and Snowsight. The console steps are in the
-- comments; run the SQL statements in a Snowsight worksheet as ACCOUNTADMIN.
-- Replace <your-account-id>, <your-region>, and <your-api-id> with your values.
-- =============================================================================

-- REGION: create the Lambda, API Gateway and IAM role in AWS us-east-1; keep <your-region> = us-east-1 consistent below.

-- ---- In the AWS console: build the Lambda function ----
-- 1. Open the Lambda service. Click Create function, author from scratch, name it
--    order-tax, runtime Python 3.12. Create it, then paste this code and Deploy.
--    It reads the Snowflake batch, adds 8% sales tax to each amount, and returns
--    one value per row in the shape Snowflake expects:
--
--      import json
--      def lambda_handler(event, context):
--          body = json.loads(event["body"])
--          rows = body["data"]
--          out = []
--          for row in rows:
--              row_idx = row[0]
--              amount  = row[1]
--              taxed   = round(float(amount) * 1.08, 2)
--              out.append([row_idx, taxed])
--          return {"statusCode": 200, "body": json.dumps({"data": out})}

-- ---- In the AWS console: front the Lambda with API Gateway ----
-- 2. Open API Gateway. Create a REST API (not HTTP API), regional endpoint,
--    name it snowflake-ext-func-api.
-- 3. Create a Resource named snowflake, then create a POST method on it.
--    Integration type: Lambda Function, Use Lambda Proxy integration = ON,
--    point it at the order-tax function.
-- 4. On that POST method, set Method Request > Authorization = AWS_IAM. This is
--    what forces every call to be signed by a trusted IAM role.
-- 5. Deploy the API to a stage named prod. Copy the Invoke URL. It looks like
--    https://<your-api-id>.execute-api.<your-region>.amazonaws.com/prod/snowflake

-- ---- In the AWS console: the IAM role Snowflake will assume ----
-- 6. Open IAM, create a role. For the trusted entity choose your own account for
--    now (a placeholder we fix in step 11). Name it snowflake-ext-func-api-role.
-- 7. Attach an inline policy that lets the role invoke the API:
--      {
--        "Version": "2012-10-17",
--        "Statement": [{
--          "Effect": "Allow",
--          "Action": "execute-api:Invoke",
--          "Resource": "arn:aws:execute-api:<your-region>:<your-account-id>:<your-api-id>/*/POST/snowflake"
--        }]
--      }
--    Copy the role ARN.

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS EXTFUNC_LAB;
CREATE SCHEMA   IF NOT EXISTS EXTFUNC_LAB.EXT;
USE SCHEMA EXTFUNC_LAB.EXT;

-- ---- In Snowsight ----

-- 8. Create the API integration. It names the role Snowflake will assume, and
--    pins the exact endpoint prefix it is allowed to reach.
CREATE OR REPLACE API INTEGRATION order_tax_api_int
  API_PROVIDER = aws_api_gateway
  API_AWS_ROLE_ARN = 'arn:aws:iam::<your-account-id>:role/snowflake-ext-func-api-role'
  API_ALLOWED_PREFIXES = ('https://<your-api-id>.execute-api.<your-region>.amazonaws.com/prod/snowflake')
  ENABLED = TRUE;

-- 9. Read back the identity Snowflake minted for this integration. You need both.
DESC INTEGRATION order_tax_api_int;
--    Note API_AWS_IAM_USER_ARN  (a Snowflake-owned IAM user ARN)
--    Note API_AWS_EXTERNAL_ID   (a unique external id for this integration)

-- ---- Back in the AWS console: fix the role's trust (the make-or-break step) ----
-- 10. Open snowflake-ext-func-api-role and edit its trust relationship. Set the
--     Principal to the API_AWS_IAM_USER_ARN, and add a Condition requiring
--     sts:ExternalId to equal the API_AWS_EXTERNAL_ID. Save it:
--       {
--         "Version": "2012-10-17",
--         "Statement": [{
--           "Effect": "Allow",
--           "Principal": { "AWS": "<API_AWS_IAM_USER_ARN>" },
--           "Action": "sts:AssumeRole",
--           "Condition": { "StringEquals": { "sts:ExternalId": "<API_AWS_EXTERNAL_ID>" } }
--         }]
--       }
--     Without this, every call returns a 403 and the function fails.

-- ---- Back in Snowsight ----

-- 11. Create the external function. It points at the Invoke URL through the
--     integration. The signature and return type are the SQL contract.
CREATE OR REPLACE EXTERNAL FUNCTION add_sales_tax(amount FLOAT)
  RETURNS FLOAT
  API_INTEGRATION = order_tax_api_int
  AS 'https://<your-api-id>.execute-api.<your-region>.amazonaws.com/prod/snowflake';

-- 12. Call it like any function. Snowflake batches the rows out to Lambda and
--     merges the returned values back in.
SELECT add_sales_tax(100)    AS a,      -- 108.00
       add_sales_tax(250.50) AS b;      -- 270.54

-- 13. Apply it across a table to see the batching in action.
CREATE OR REPLACE TABLE orders_raw (order_id INT, product STRING, amount FLOAT);
INSERT INTO orders_raw VALUES
  (1,'Keyboard',49.99),(2,'Monitor',219.00),(3,'Laptop',1299.00);

SELECT order_id, product, amount, add_sales_tax(amount) AS amount_with_tax
FROM orders_raw ORDER BY order_id;
--    49.99 -> 53.99, 219.00 -> 236.52, 1299.00 -> 1402.92

-- ---- Cleanup (optional, run this when you are done) ----
-- In Snowsight:
--   DROP FUNCTION IF EXISTS add_sales_tax(FLOAT);
--   DROP TABLE IF EXISTS orders_raw;
--   DROP INTEGRATION IF EXISTS order_tax_api_int;
-- In the AWS console, delete the API Gateway REST API, the order-tax Lambda
-- function, and the snowflake-ext-func-api-role so nothing keeps billing.
