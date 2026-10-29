#!/usr/bin/env bash
# =============================================================================
# 04  Start Kafka and Kafka Connect in Docker, then wait until the Snowflake
#     connector plugin is installed and the Connect REST API answers.
#
#   Mac / Linux : bash 04_start_kafka.sh
#   Windows     : run from Git Bash (or WSL) with Docker Desktop running.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running. Start Docker Desktop, wait until it says"
  echo "'Engine running', then run this script again."
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  echo "Docker Compose not found. Update Docker Desktop to a current version."
  exit 1
fi

echo "Starting voltway-kafka and voltway-connect (the first run downloads the images)..."
$COMPOSE up -d

echo
echo "Waiting for Kafka Connect to install the Snowflake connector plugin."
echo "This usually takes 1 to 3 minutes."
PLUGIN="com.snowflake.kafka.connector.SnowflakeSinkConnector"
for i in $(seq 1 60); do
  if curl -s -m 5 http://localhost:8083/connector-plugins 2>/dev/null | grep -q "$PLUGIN"; then
    echo
    echo "Kafka Connect is ready and the Snowflake connector plugin is installed:"
    curl -s http://localhost:8083/connector-plugins | grep -o "\"class\":\"$PLUGIN\",\"type\":\"sink\",\"version\":\"[^\"]*\""
    exit 0
  fi
  printf "."
  sleep 5
done

echo
echo "Kafka Connect did not become ready within 5 minutes. Check its log with:"
echo "    docker logs --tail 50 voltway-connect"
exit 1
