#!/usr/bin/env bash
# =============================================================================
# 06  Produce one wave of Voltway events into Kafka.
#
#   bash 06_produce_events.sh 1   morning traffic (08:00 to 11:00)
#   bash 06_produce_events.sh 2   midday traffic, re-sent duplicates, one broken message
#   bash 06_produce_events.sh 3   late backlog from a charger that lost its network link
#
# Each message is keyed by charger_id. Kafka hashes the key to pick the
# partition, so all events from one charger stay in one partition, in order.
# Windows: run from Git Bash (or WSL) with Docker Desktop running.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

WAVE="${1:-}"
case "$WAVE" in
  1|2|3) ;;
  *) echo "Usage: bash 06_produce_events.sh <1|2|3>"; exit 1 ;;
esac

DATA="dataset"
EVENTS="$DATA/wave${WAVE}_charging_events.jsonl"
STATUS="$DATA/wave${WAVE}_charger_status.jsonl"
for f in "$EVENTS" "$STATUS"; do
  [ -f "$f" ] || { echo "Missing $f. Run this from the starter kit folder, next to dataset/."; exit 1; }
done
docker ps --format '{{.Names}}' | grep -q '^voltway-kafka$' \
  || { echo "voltway-kafka is not running. Run: bash 04_start_kafka.sh"; exit 1; }
for t in charging_events charger_status; do
  docker exec voltway-kafka kafka-topics --bootstrap-server kafka:29092 --list | grep -qx "$t" \
    || { echo "Topic $t does not exist. Run: bash 05_create_topics.sh"; exit 1; }
done

# Turn each JSON line into "charger_id|json" so the console producer can split
# the key from the value at the | character.
produce() {
  local file="$1" topic="$2"
  sed -E 's/^(.*"charger_id":"([^"]+)".*)$/\2|\1/' "$file" \
    | docker exec -i voltway-kafka kafka-console-producer \
        --bootstrap-server kafka:29092 --topic "$topic" \
        --property parse.key=true --property "key.separator=|"
  echo "  $(grep -c . "$file") messages -> $topic"
}

echo "Producing wave $WAVE..."
produce "$EVENTS" charging_events
produce "$STATUS" charger_status
echo
echo "Done. If your connector is running, the rows land in Snowflake within seconds."
