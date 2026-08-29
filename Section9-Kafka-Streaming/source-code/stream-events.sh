#!/usr/bin/env bash
# Stream events end to end: create the topic, register the Snowflake connector,
# and produce sample records. Run after "docker compose up -d" and after the
# Connect REST API is live at http://localhost:8083 (give it a minute to install
# the connector plugin). snowflake-sink-connector.json must sit next to this file
# with your account, user, and private key filled in.
set -euo pipefail

# 1. Create the topic the connector listens to.
docker exec s9-kafka kafka-topics --bootstrap-server kafka:29092 \
  --create --if-not-exists --topic product_events --partitions 1 --replication-factor 1

# 2. Register the connector against the Kafka Connect REST API.
curl -s -X POST -H "Content-Type: application/json" \
  --data @snowflake-sink-connector.json \
  http://localhost:8083/connectors | python3 -m json.tool

# 3. Confirm the connector and its task are RUNNING before producing.
sleep 10
curl -s http://localhost:8083/connectors/snowflake-sink/status | python3 -m json.tool

# 4. Produce five JSON events into the topic.
printf '%s\n' \
  '{"event_id":1,"product":"Keyboard","qty":2,"price":45.00}' \
  '{"event_id":2,"product":"Mouse","qty":1,"price":19.99}' \
  '{"event_id":3,"product":"Monitor","qty":1,"price":229.00}' \
  '{"event_id":4,"product":"Webcam","qty":3,"price":59.50}' \
  '{"event_id":5,"product":"Desk Mat","qty":1,"price":12.00}' \
  | docker exec -i s9-kafka kafka-console-producer \
      --bootstrap-server kafka:29092 --topic product_events

echo
echo "Events produced. Within about 10 seconds they land in KAFKA_LAB.KAFKA.PRODUCT_EVENTS."
echo "Now run verify.sql in Snowsight."

# Teardown when you are done (stops and removes the containers and volumes):
#   docker compose down -v
