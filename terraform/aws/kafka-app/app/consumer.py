"""Consumer: reads the topic named in SSM and counts messages for the dashboard.

Two configuration sources with different refresh semantics, chosen so each demo
produces a distinct, visible failure mode:

  * Topic  -> read from SSM Parameter Store and re-checked every few seconds, so
    the "wiring" demo (change the SSM value to orders-v2) makes the consumer
    silently re-subscribe to an empty topic. The counter freezes with NO error.

  * Broker connectivity / IAM auth -> re-established on every (re)connect. The
    "firewall" demo (revoke the SG rule) surfaces as connection timeouts; the
    "revoked access" demo (detach the IAM policy) surfaces as auth errors. Both
    freeze the counter WITH a clear error on the dashboard.
"""

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
                # the wired topic. A change means the operator (or a break script)
                # re-pointed us; re-subscribe cleanly.
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
            msg = str(exc)
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
