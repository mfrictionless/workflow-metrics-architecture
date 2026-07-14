#!/bin/sh
# M2.2 regression check: a single-node Kafka broker (KRaft mode, no
# Zookeeper) starts, accepts admin/client connections, and can create/list
# topics. These 4 topics are a basic health check, not the final CDC topic
# topology -- Debezium (M2.3) will create its own topics with its own
# naming convention. See design/Milestones.md M2.2.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$ROOT"

cleanup() { ./scripts/compose_down.sh >/dev/null 2>&1 || true; }
trap cleanup EXIT

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

docker compose up -d kafka >/dev/null 2>&1 || {
  printf 'FAIL: docker compose up -d kafka failed\n' >&2
  exit 1
}

# Wait for the broker to accept connections.
ready=0
i=0
while [ "$i" -lt 30 ]; do
  if docker compose exec -T kafka /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 >/dev/null 2>&1; then
    ready=1
    break
  fi
  i=$((i + 1))
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  printf 'FAIL: Kafka broker did not become ready within 30s\n' >&2
  exit 1
fi

# Create and list the 4 health-check topics.
for t in files file_actions parties audit_events; do
  docker compose exec -T kafka /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 --create --topic "$t" --partitions 1 --replication-factor 1 >/dev/null 2>&1 \
    || err "failed to create topic '$t'"
done

topics=$(docker compose exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list)
for t in files file_actions parties audit_events; do
  printf '%s' "$topics" | grep -qx "$t" || err "topic '$t' not found in topic list"
done

# No Zookeeper anywhere in the stack -- confirms KRaft-only, per M2.2's
# explicit test.
if docker ps --format '{{.Image}}' | grep -qi zookeeper; then
  err "a Zookeeper container is running -- this milestone requires KRaft only, no Zookeeper"
fi

if [ "$fail" -ne 0 ]; then
  printf '\nkafka check FAILED\n' >&2
  exit 1
fi
printf 'kafka check passed\n'
