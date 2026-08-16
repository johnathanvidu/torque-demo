"""Shared helpers for the Kafka demo producer/consumer/dashboard.

The three processes all read their configuration from environment variables
(populated by /etc/kafka-demo/config.env, written by the instance user-data) and
authenticate to MSK using IAM — the EC2 instance role is signed into a short-lived
OAUTHBEARER token on every (re)connection.
"""

import json
import os
import tempfile
import time

from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

try:
    from kafka.oauth.abstract import AbstractTokenProvider
except Exception:  # pragma: no cover - fallback if the import path changes
    class AbstractTokenProvider:  # type: ignore
        pass

REGION = os.environ.get("AWS_REGION", "eu-west-1")
BROKERS = os.environ.get("BROKERS", "")
PRODUCER_TOPIC = os.environ.get("PRODUCER_TOPIC", "orders")
TOPIC_PARAM = os.environ.get("TOPIC_PARAM", "/kafka-demo/consumer-topic")
CONSUMER_GROUP = os.environ.get("CONSUMER_GROUP", "kafka-demo-consumers")
STATUS_FILE = os.environ.get("STATUS_FILE", "/var/lib/kafka-demo/status.json")


class MSKTokenProvider(AbstractTokenProvider):
    """Hands kafka-python a fresh MSK IAM auth token on demand."""

    def token(self):
        token, _expiry_ms = MSKAuthTokenProvider.generate_auth_token(REGION)
        return token


def kafka_iam_kwargs():
    """Common kafka-python connection kwargs for MSK IAM auth."""
    return dict(
        bootstrap_servers=BROKERS.split(","),
        security_protocol="SASL_SSL",
        sasl_mechanism="OAUTHBEARER",
        sasl_oauth_token_provider=MSKTokenProvider(),
    )


def write_status(status: dict):
    """Atomically publish the consumer's current status for the dashboard."""
    os.makedirs(os.path.dirname(STATUS_FILE), exist_ok=True)
    status = {**status, "updated_at": time.time()}
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(STATUS_FILE))
    with os.fdopen(fd, "w") as f:
        json.dump(status, f)
    os.replace(tmp, STATUS_FILE)


def read_status() -> dict:
    try:
        with open(STATUS_FILE) as f:
            return json.load(f)
    except Exception:
        return {}
