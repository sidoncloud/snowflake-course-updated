# Copperleaf Insurance: UDFs, UDTFs and Stored Procedures Assignment (Starter Kit)

## The scenario

Copperleaf Insurance receives claim submissions from brokers in several countries, and every broker's system sends them in a different shape. Policy numbers come in four styles, dates in five formats, amounts in five currencies, and the adjuster notes are free text that hides fraud signals. The claims team wants a clean, scored claims table that refreshes itself every few minutes, processes only what's new, and hands them a queue of the claims a person needs to look at.

## The data you get

Everything is inline in `starter.sql`, so there is nothing to upload.

- `claims_raw`: 8 broker claims (CLM-1001 to CLM-1008) with messy policy numbers, dates, local currency amounts and adjuster notes. A `load_ts` column records when each row landed.
- `fx_rates`: one USD conversion rate for each of USD, GBP, EUR, AED and INR.
- A second batch of 3 claims (two new ones and a resubmission of CLM-1003), in a clearly marked block inside Task 4. Run it only when that block tells you to.

All names are synthetic.

## Your tasks

1. Clean up policy numbers and dates, whatever format they arrive in
2. Convert every amount to US dollars and give each claim a severity
3. Pull the fraud signals out of the adjuster notes
4. Process only new claims, and update resubmitted ones in place
5. Run it on a schedule, with a record of every run
6. Give the claims team a queue of claims that need a person

The exact business rules for each task (the policy number format, the severity thresholds, the fraud phrases, what goes in the review queue) are written in the comments of `starter.sql`.

## Prerequisites

- A Snowflake trial account with the ACCOUNTADMIN role. Python UDFs use packages from the Snowflake Anaconda channel, which a trial account can use once you accept the Anaconda terms (in Snowsight under Admin, then Terms; older versions call it Billing and Terms) if you are asked to.

## How to start

1. Open a new SQL worksheet in Snowsight and paste in `starter.sql`.
2. Run the SETUP block. It creates `COPPERLEAF_WH`, the `COPPERLEAF.CLAIMS` schema, `claims_raw` and `fx_rates`.
3. Work through the tasks in order. Each task builds on the functions from the ones before it.
4. Don't run the SECOND BATCH block in Task 4 until your procedure has processed the first 8 claims.

## Files

- `starter.sql`: setup, raw data, the second batch, and one TODO section per task.

Full solution with a step-by-step walkthrough and source code: https://cognifydata.com/labs/snowpark-udfs-udtfs-stored-procedures-insurance-claims (free, no sign-up).
