"""Producer: writes one order event per interval to the wired topic.

The producer topic is fixed at boot from the blueprint-wired value (PRODUCER_TOPIC).
It never reads the mutable SSM parameter — that is deliberately only the consumer's
input, so the "grain I/O wiring" demo can drift the consumer's topic away from the
producer's and create a silent mismatch.
"""

import json
import time

from kafka import KafkaProducer

import common


def build_producer():
    return KafkaProducer(
        value_serializer=lambda v: json.dumps(v).encode("utf-8"),
        retries=5,
        **common.kafka_iam_kwargs(),
    )


def main():
    producer = None
    n = 0
    while True:
        try:
            if producer is None:
                print(f"[producer] connecting to {common.BROKERS} ...", flush=True)
                producer = build_producer()
                print(f"[producer] connected; producing to '{common.PRODUCER_TOPIC}'", flush=True)

            n += 1
            event = {"id": n, "amount": (n * 7) % 500, "ts": time.time()}
            producer.send(common.PRODUCER_TOPIC, event)
            producer.flush(timeout=10)
            if n % 10 == 0:
                print(f"[producer] sent {n} events", flush=True)
            time.sleep(3)
        except Exception as exc:  # noqa: BLE001 - keep the process alive and retry
            print(f"[producer] ERROR: {exc}", flush=True)
            try:
                if producer is not None:
                    producer.close(timeout=1)
            except Exception:
                pass
            producer = None
            time.sleep(5)


if __name__ == "__main__":
    main()
