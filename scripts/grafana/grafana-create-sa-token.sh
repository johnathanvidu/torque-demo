#!/usr/bin/env bash
#
# post-helm-install script for the Grafana grain.
#
# Runs on the Kubernetes agent (in-cluster) once Grafana is deployed. It waits
# for Grafana to become healthy, then mints a fresh service-account token via the
# Grafana HTTP API using the admin credentials. The token is emitted as a grain
# output (service_account_token) and wired — dynamically, at deploy time — into
# the Grafana MCP server. Nothing is hardcoded: the MCP server's auth is computed
# here.
#
# Args (positional):
#   $1  Grafana base URL, in-cluster (e.g. http://grafana.graphana.svc.cluster.local:3000)
#   $2  Grafana admin username
#   $3  Grafana admin password
#   $4  service account name
#   $5  service account token name
#
# Emits (Torque captures "name=value" lines declared under the grain's
# scripts.post-helm-install.outputs):
#   grafana_url=<url>
#   service_account_token=<token>
set -euo pipefail

GRAFANA_URL="${1:?grafana url required}"
ADMIN_USER="${2:?admin user required}"
ADMIN_PASSWORD="${3:?admin password required}"
SA_NAME="${4:-torque-mcp}"
TOKEN_NAME="${5:-torque-mcp-token}"

AUTH="${ADMIN_USER}:${ADMIN_PASSWORD}"

echo "Waiting for Grafana at ${GRAFANA_URL} to become healthy..." >&2
for i in $(seq 1 60); do
  if curl -sf -o /dev/null "${GRAFANA_URL}/api/health"; then
    echo "Grafana is healthy." >&2
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERROR: Grafana did not become healthy in time." >&2
    exit 1
  fi
  sleep 5
done

# Make token minting idempotent: if a service account with this name already
# exists (e.g. on a redeploy), delete it so we always emit a fresh, valid token.
existing_id="$(curl -sf -u "${AUTH}" \
  "${GRAFANA_URL}/api/serviceaccounts/search?query=${SA_NAME}" \
  | grep -o "\"name\":\"${SA_NAME}\"[^}]*" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2 || true)"

if [ -n "${existing_id}" ]; then
  echo "Removing existing service account id=${existing_id}" >&2
  curl -sf -X DELETE -u "${AUTH}" "${GRAFANA_URL}/api/serviceaccounts/${existing_id}" >/dev/null || true
fi

echo "Creating service account '${SA_NAME}'..." >&2
sa_resp="$(curl -sf -u "${AUTH}" -H 'Content-Type: application/json' \
  -X POST "${GRAFANA_URL}/api/serviceaccounts" \
  -d "{\"name\":\"${SA_NAME}\",\"role\":\"Admin\",\"isDisabled\":false}")"
sa_id="$(echo "${sa_resp}" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)"

if [ -z "${sa_id}" ]; then
  echo "ERROR: could not create service account. Response: ${sa_resp}" >&2
  exit 1
fi

echo "Creating token '${TOKEN_NAME}' for service account id=${sa_id}..." >&2
tok_resp="$(curl -sf -u "${AUTH}" -H 'Content-Type: application/json' \
  -X POST "${GRAFANA_URL}/api/serviceaccounts/${sa_id}/tokens" \
  -d "{\"name\":\"${TOKEN_NAME}\"}")"
token="$(echo "${tok_resp}" | grep -o '"key":"[^"]*"' | head -1 | sed 's/.*"key":"//;s/"$//')"

if [ -z "${token}" ]; then
  echo "ERROR: could not create service account token. Response: ${tok_resp}" >&2
  exit 1
fi

echo "Service-account token minted successfully." >&2

# Torque captures these as grain outputs.
echo "grafana_url=${GRAFANA_URL}"
echo "service_account_token=${token}"
