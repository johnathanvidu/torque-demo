"""Consumer: reads the topic named in SSM and counts messages for the dashboard.

Two configuration sources, with deliberately different refresh semantics:

  * Topic -> read from SSM Parameter Store and re-checked every few seconds, so
    the subscription can be repointed at runtime without restarting the process.
    A change takes effect silently: the consumer re-subscribes, and if the new
    topic has no producer it simply stops counting, raising no error.

  * Broker connectivity -> re-established on every (re)connect. A network-level
    block is told apart from a broker-side failure by a quick TCP probe.

The message count is persisted to the status file and reloaded on startup, so a
restart resumes the counter where it left off rather than snapping back to zero.
"""

import socket
import time

import boto3
from kafka import KafkaConsumer

import common

ssm = boto3.client("ssm", region_name=common.REGION)

count = 0
last_message_ts = None


def current_topic(previous=None):
    """Return the topic the consumer should be on, per SSM. Falls back to the
    previously known topic (or the producer topic) if SSM is unreachable."""
    try:
        resp = ssm.get_parameter(Name=common.TOPIC_PARAM)
        return resp["Parameter"]["Value"]
    except Exception as exc:  # noqa: BLE001
        print(f"[consumer] WARN: could not read topic from SSM ({exc})", flush=True)
        return previous or common.PRODUCER_TOPIC


def broker_reachable():
    """Quick TCP probe of the first bootstrap broker, so a network-level block can
    be told apart from a broker-side failure. Returns (ok, host:port)."""
    first = common.BROKERS.split(",")[0].strip()
    host, _, port = first.partition(":")
    port = int(port or "9098")
    try:
        with socket.create_connection((host, port), timeout=3):
            return True, f"{host}:{port}"
    except Exception:
        return False, f"{host}:{port}"


def classify_error(exc):
    ok, endpoint = broker_reachable()
    if not ok:
        return f"No network route to the brokers ({endpoint})."
    return f"Reached the broker, but the Kafka connection failed: {exc}"


def publish(state, topic, error=None):
    common.write_status({
        "state": state,
        "topic": topic,
        "count": count,
        "last_message_ts": last_message_ts,
        "brokers": common.BROKERS,
        "last_error": error,
    })


def main():
    global count, last_message_ts
    # Resume the counter across restarts.
    prev = common.read_status()
    count = prev.get("count", 0) or 0
    last_message_ts = prev.get("last_message_ts")

    topic = current_topic()
    publish("starting", topic)

    while True:
        consumer = None
        try:
            print(f"[consumer] connecting to {common.BROKERS}, topic '{topic}' ...", flush=True)
            consumer = KafkaConsumer(
                topic,
                group_id=common.CONSUMER_GROUP,
                auto_offset_reset="latest",
                consumer_timeout_ms=2000,
                **common.kafka_iam_kwargs(),
            )
            print(f"[consumer] connected; consuming '{topic}'", flush=True)
            publish("connected", topic)
            last_topic_check = 0.0

            while True:
                for message in consumer:
                    count += 1
                    last_message_ts = time.time()
                    if count % 10 == 0:
                        print(f"[consumer] consumed {count} messages", flush=True)
                    publish("connected", topic)

                # consumer_timeout_ms fires when idle: refresh status + re-check
                # the wired topic. A change means we were re-pointed at runtime;
                # re-subscribe cleanly.
                publish("connected", topic)
                now = time.time()
                if now - last_topic_check > 5:
                    last_topic_check = now
                    desired = current_topic(previous=topic)
                    if desired != topic:
                        print(f"[consumer] topic changed '{topic}' -> '{desired}', re-subscribing", flush=True)
                        topic = desired
                        break  # drop out to rebuild the consumer on the new topic
        except Exception as exc:  # noqa: BLE001
            msg = classify_error(exc)
            print(f"[consumer] ERROR: {msg}", flush=True)
            publish("error", topic, error=msg)
            time.sleep(5)
            topic = current_topic(previous=topic)
        finally:
            if consumer is not None:
                try:
                    consumer.close()
                except Exception:
                    pass


if __name__ == "__main__":
    main()
