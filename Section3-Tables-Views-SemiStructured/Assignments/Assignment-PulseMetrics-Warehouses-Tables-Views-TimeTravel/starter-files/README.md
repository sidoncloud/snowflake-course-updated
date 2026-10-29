# PulseMetrics: Snowflake Core Assignment (Starter Kit)

## The scenario

PulseMetrics is a B2B SaaS analytics platform, and every action a customer takes in the product becomes a usage event. Those events arrive as nested JSON, and one event can hold several feature line items. Analysts want fast rollups, finance wants billing data kept away from everyone else, and the platform team wants the compute bill capped. Then an engineer runs a DELETE with a WHERE clause that is too broad, and you have to get the data back.

## The data you get

Everything is inline in `starter.sql`, so there is nothing to upload.

- `accounts`: 8 customer accounts (company, plan tier, country, sign-up time, monthly recurring revenue).
- `subscriptions`: 8 subscriptions (plan tier, seats, monthly price, status).
- `usage_events_staging`: 6 raw JSON usage events, each with a nested `features` array.

## Your tasks

1. Set up compute for loading and for analysts, and cap the spend
2. Pick the right table type for each table
3. Turn the nested JSON events into rows analysts can query
4. Give each team its own view, with billing visible only to finance
5. Recover the deleted data and the dropped table
6. Give the team a dev copy of the schema for risky changes

## Prerequisites

- A Snowflake trial account (any edition that supports materialized views, such as Enterprise), with the ACCOUNTADMIN role.

## How to start

1. Open a new SQL worksheet in Snowsight and paste in `starter.sql`.
2. Run the SETUP block.
3. Do Task 1 first, because the data load needs a running warehouse.
4. Do Task 2, then run the DATA LOAD block. The INSERTs only work once your three tables exist with the column lists given in the comments.
5. Work through Tasks 3 to 6 in order. Task 5 starts with a given DELETE that simulates the incident.

## Files

- `starter.sql`: setup, data load, and one TODO section per task.

Full solution with a step-by-step walkthrough and source code: https://cognifydata.com/labs/saas-snowflake-core-fundamentals (free, no sign-up).
