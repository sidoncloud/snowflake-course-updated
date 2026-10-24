#!/usr/bin/env bash
# Send one more event into the product_events topic, after stream-events.sh has
# run. Then re-run step 1 of verify.sql in Snowsight: the count goes from 5 to 6.
#
#   Mac / Linux : bash send-one-event.sh
#   Windows     : run it from Git Bash or WSL, with Docker Desktop running.
set -euo pipefail

echo '{"event_id":6,"product":"USB Hub","qty":2,"price":24.99}' \
  | docker exec -i s9-kafka kafka-console-producer \
      --bootstrap-server kafka:29092 --topic product_events

echo "Sent event_id 6. Re-run step 1 of verify.sql in about 10 seconds."
