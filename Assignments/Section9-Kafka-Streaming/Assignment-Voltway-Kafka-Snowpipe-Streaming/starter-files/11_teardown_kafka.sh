#!/usr/bin/env bash
# =============================================================================
# 11  Tear down the local Kafka side and delete the secrets from this folder.
#
#   1. Deletes every registered connector (it closes its Snowflake channels cleanly).
#   2. Stops and removes both containers, their network and their data.
#   3. Deletes rsa_key.p8, rsa_key.pub and voltway-sink-connector.json.
#
#   Mac / Linux : bash 11_teardown_kafka.sh
#   Windows     : run from Git Bash (or WSL) with Docker Desktop running.
# Then run the cleanup block at the end of starter.sql in Snowsight.
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")"

if curl -s -m 5 -o /dev/null http://localhost:8083/ 2>/dev/null; then
  for c in $(curl -s -m 10 http://localhost:8083/connectors | tr -d '[]"' | tr ',' ' '); do
    echo "Deleting connector $c..."
    curl -s -m 30 -X DELETE "http://localhost:8083/connectors/$c" >/dev/null
  done
  sleep 5
fi

if docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"; else COMPOSE="docker-compose"; fi
echo "Removing containers, network and volumes..."
$COMPOSE down -v --remove-orphans

echo "Deleting the key pair and the filled-in connector config, if present..."
rm -f rsa_key.p8 rsa_key.pub voltway-sink-connector.json

echo
echo "Left behind on purpose: the two Docker images (cp-kafka and cp-kafka-connect-base,"
echo "about 2 GB together) so a re-run starts fast. To remove them too:"
echo "    docker image rm confluentinc/cp-kafka:7.6.1 confluentinc/cp-kafka-connect-base:7.6.1"
echo
echo "Now run the cleanup block at the end of starter.sql in Snowsight."
