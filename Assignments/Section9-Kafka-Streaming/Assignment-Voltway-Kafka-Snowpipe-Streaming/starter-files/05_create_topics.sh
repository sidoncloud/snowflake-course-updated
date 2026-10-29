#!/usr/bin/env bash
# =============================================================================
# 05  Create the two Kafka topics the Voltway chargers publish to.
#
# Automatic topic creation is switched off in this broker, so every topic must
# be created explicitly. charging_events gets 3 partitions, charger_status 1.
# If your design needs any other topic, create it the same way.
#
#   Mac / Linux : bash 05_create_topics.sh
#   Windows     : run from Git Bash (or WSL) with Docker Desktop running.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

docker ps --format '{{.Names}}' | grep -q '^voltway-kafka$' \
  || { echo "voltway-kafka is not running. Run: bash 04_start_kafka.sh"; exit 1; }

create_topic() {
  docker exec voltway-kafka kafka-topics --bootstrap-server kafka:29092 \
    --create --if-not-exists --topic "$1" --partitions "$2" --replication-factor 1
}
create_topic charging_events 3
create_topic charger_status 1

echo
echo "Topics on the broker:"
docker exec voltway-kafka kafka-topics --bootstrap-server kafka:29092 --list | grep -v "^_"
