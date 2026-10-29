# Voltway: Kafka, Snowpipe Streaming and Dynamic Tables Assignment (Starter Kit)

## The scenario

Voltway runs 12 EV fast chargers across 5 stations, and every charger publishes charging-session events and status changes to Kafka. The operations team wants those events in Snowflake within seconds, with no batch load jobs, and turned into live sessions, hourly station KPIs and charger health. Real Kafka traffic isn't clean: some events get delivered twice, one message arrives broken, and a charger that lost its network uploads its backlog hours late. Your pipeline has to handle all three without anyone touching it.

## The data you get

Six newline-delimited JSON files in `dataset/`, one line per Kafka message, for one day (27 Oct 2026, UTC). `06_produce_events.sh` sends them to Kafka, keyed by `charger_id`.

| File | Messages | What it simulates |
|---|---|---|
| `wave1_charging_events.jsonl` | 196 | Morning traffic, 08:00 to 11:00 |
| `wave1_charger_status.jsonl` | 86 | Morning status changes |
| `wave2_charging_events.jsonl` | 186 | Midday traffic, including some re-sent duplicates and one broken message |
| `wave2_charger_status.jsonl` | 67 | Midday status changes |
| `wave3_charging_events.jsonl` | 12 | Late backlog from CHG-11, which lost its network link from 08:45 to 10:40 |
| `wave3_charger_status.jsonl` | 4 | The statuses CHG-11 buffered during the outage |

Topic `charging_events`:
- `event_id`, `event_type` (`session_started`, `meter_update`, `session_stopped`), `session_id`, `charger_id`, `station_id`
- `event_ts` (ISO 8601, UTC), `meter_kwh` (cumulative energy in the session), `power_kw`
- `vehicle` object on `session_started` only: `make`, `connector`, `battery_pct`
- `payment` object on `session_started` only: `method`
- `stop_reason` on `session_stopped` only

Topic `charger_status`:
- `charger_id`, `station_id`, `status` (AVAILABLE, CHARGING, FAULTED, OFFLINE), `error_code`, `reported_at`

`starter.sql` also creates a `STATIONS` table with each station's tariff in USD per kWh. All names are synthetic.

## Your tasks

1. Give the Kafka connector its own secure login, with least privilege
2. Stream both Kafka topics into Snowflake, with no load jobs
3. Turn raw events into sessions, hourly KPIs and charger health
4. Make sure duplicate events don't inflate the numbers
5. Keep a broken message from stopping the pipeline
6. Let late events correct the numbers already reported

## Prerequisites

- A Snowflake trial account with the ACCOUNTADMIN role.
- Docker Desktop, installed and running.
- A bash terminal with `openssl` and `curl`: Terminal on macOS or Linux, Git Bash or WSL on Windows. Command Prompt and PowerShell can't run these scripts.

## How to start

1. Open a new SQL worksheet in Snowsight, paste in `starter.sql`, and run the SETUP block. It creates `VOLTWAY_WH`, the `VOLTWAY.STREAMING` schema and the `STATIONS` table.
2. In your terminal, from this folder, run `bash 04_start_kafka.sh`. It starts one Kafka broker and one Kafka Connect worker in Docker, with the Snowflake Kafka connector plugin installed, and waits until they are ready.
3. Run `bash 05_create_topics.sh` to create the `charging_events` and `charger_status` topics. Automatic topic creation is off on this broker.
4. Work through the tasks. Kafka Connect's REST API is at http://localhost:8083. Produce each wave only when a task asks for it: `bash 06_produce_events.sh 1`, then `2`, then `3`.
5. When you are done, run `bash 11_teardown_kafka.sh`, then the cleanup block at the end of `starter.sql`.

## Files

- `starter.sql`: setup, station data, and one TODO section per task.
- `docker-compose.yml`: Kafka (KRaft mode, no ZooKeeper) and Kafka Connect with the Snowflake connector.
- `04_start_kafka.sh`: starts the containers and waits for the connector plugin.
- `05_create_topics.sh`: creates the two data topics.
- `06_produce_events.sh`: sends one wave of events from `dataset/`.
- `11_teardown_kafka.sh`: deletes your connectors, the containers and their data, and any key files in this folder.
- `.gitignore`: keeps the key files you create out of git. Never commit a private key.
- `dataset/`: the six event files.

Full solution with a step-by-step walkthrough and source code: https://cognifydata.com/labs/snowflake-kafka-snowpipe-streaming-dynamic-tables (free, no sign-up).
