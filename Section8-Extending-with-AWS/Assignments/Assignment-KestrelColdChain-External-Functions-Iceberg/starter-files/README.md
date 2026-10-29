# Kestrel Cold Chain: External Functions and Iceberg Assignment (Starter Kit)

## The scenario

Kestrel Cold Chain is a refrigerated freight forwarder in Rotterdam, and it has to report the CO2e of every shipment it moves. The emissions maths belongs to the sustainability team, who run it as an AWS Lambda service, so Snowflake must call that service rather than copy the formulas into SQL. The scored shipments have to be stored in Kestrel's own S3 bucket in an open format the auditors' tools can read. Corrections, cancellations and late shipments keep arriving after the first report, and the auditors want to see what a value was before it was fixed.

## The data you get

The shipment data is built inline in `starter.sql`, so there is nothing to upload.

- `lanes`: 10 freight lanes out of Rotterdam and Amsterdam (ROAD, RAIL, SEA, AIR) with a distance in km, plus one DRONE pilot lane the service doesn't support.
- `shipments`: 480 Q3 2026 shipments generated with fixed formulas, so everyone gets the same numbers, plus 3 bad records (a drone shipment, a missing weight and a negative weight). 483 in total.
- `late_shipments`: 5 late or corrected records, in a marked block inside Task 5.

You also get the sustainability team's service, which you deploy but don't change:

- `lambda/lambda_function.py`: the CO2e calculator (Python 3.12, no dependencies). Its header explains the request and response format.
- `lambda/test_event.json`: a Lambda console test event shaped like a request from Snowflake through API Gateway.

All names are synthetic, and the emission factors are illustrative, not for real carbon reporting.

## Your tasks

1. Put the calculator behind an endpoint only Snowflake can call
2. Score every shipment from Snowflake, with no maths copied into SQL
3. Set bad records aside so they don't fail the whole run
4. Store the results in your own S3, in a format other tools can read
5. Handle corrections and late shipments, and show the value before a fix
6. Publish a monthly report for the auditors

## What you'll create in AWS (high level)

- A Lambda function running `lambda_function.py`.
- A REST API in API Gateway with one POST method that calls the Lambda and requires AWS IAM authorization, deployed to a stage.
- An IAM role that Snowflake assumes to call that API, allowed to invoke only that method, with a trust policy locked to your Snowflake account.
- An S3 bucket in the same region as your Snowflake account.
- A second IAM role that Snowflake assumes to read and write that bucket, limited to one prefix, with its own trust policy locked to your Snowflake account.

Working out the exact policies and the Snowflake objects that connect to them is part of the assignment.

## Prerequisites

- A Snowflake trial account with the ACCOUNTADMIN role, on AWS.
- Your own AWS account, with permission to create Lambda functions, API Gateway APIs, IAM roles and S3 buckets. The resources cost little to nothing at this size, but delete them when you are done.

## How to start

1. Open a new SQL worksheet in Snowsight and paste in `starter.sql`.
2. Run the SETUP block. It creates `KESTREL_WH`, the `KESTREL.SUSTAINABILITY` schema, `lanes` and the 483 `shipments`, and shows your Snowflake region.
3. Start Task 1 in the AWS console: deploy `lambda/lambda_function.py` and test it with `lambda/test_event.json` before you connect Snowflake.
4. Work through the tasks in order. Run the LATE RECORDS block only when you reach Task 5.
5. IAM changes can take a minute to reach Snowflake. If a statement fails with "Error assuming AWS_ROLE" right after you edit a trust policy, wait a minute and run it again.

## Files

- `starter.sql`: setup, shipment data, the late records, and one TODO section per task.
- `lambda/lambda_function.py`: the emissions service.
- `lambda/test_event.json`: the Lambda test event.

Full solution with a step-by-step walkthrough and source code: https://cognifydata.com/labs/snowflake-external-functions-iceberg-lakehouse-shipment-emissions (free, no sign-up).
