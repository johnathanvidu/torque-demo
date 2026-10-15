#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: filter-azure-vm-by-tags.sh \
  [--tag-key <key> --tag-value <value>] \
  [--match-operator <eq|ne>] \
  [--resource-type <type>] \
  [--select <first|all>] \
  [--inactive-only | --active-only] \
  [--require-match]

Reads binding context resources from CONTRACT_FILE_PATH and exports:
  vms_json                  matching resources in [{grain_path,identifier}] format

Notes:
  - Intended for workflow scope env/env_resource with populated binding context.
  - Primary tag source path: resources[*].attributes.tags
  - Without --tag-key, resources are selected regardless of tags.
  - --resource-type also accepts a comma-separated list of types.
  - Optional env-var resource restriction JSON array:
      TORQUE_REQUESTED_RESOURCES='[{"grain_path":"my_grain","identifier":"vm-id"}]'
EOF
}

TAG_KEY=""
TAG_VALUE=""
RESOURCE_TYPE="azurerm_virtual_machine"
MATCH_OPERATOR="eq"
SELECT_MODE="first"
INACTIVE_ONLY="false"
ACTIVE_ONLY="false"
REQUIRE_MATCH="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag-key)
      TAG_KEY="$2"
      shift 2
      ;;
    --tag-value)
      TAG_VALUE="$2"
      shift 2
      ;;
    --match-operator)
      MATCH_OPERATOR="$2"
      shift 2
      ;;
    --resource-type)
      RESOURCE_TYPE="$2"
      shift 2
      ;;
    --select)
      SELECT_MODE="$2"
      shift 2
      ;;
    --inactive-only)
      INACTIVE_ONLY="true"
      shift
      ;;
    --active-only)
      ACTIVE_ONLY="true"
      shift
      ;;
    --require-match)
      REQUIRE_MATCH="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$TAG_KEY" && -z "$TAG_VALUE" ]]; then
  echo "--tag-value is required when --tag-key is set" >&2
  usage >&2
  exit 1
fi

if [[ "$INACTIVE_ONLY" == "true" && "$ACTIVE_ONLY" == "true" ]]; then
  echo "--inactive-only and --active-only are mutually exclusive" >&2
  exit 1
fi

if [[ "$MATCH_OPERATOR" != "eq" && "$MATCH_OPERATOR" != "ne" ]]; then
  echo "--match-operator must be 'eq' or 'ne'" >&2
  exit 1
fi

if [[ "$SELECT_MODE" != "first" && "$SELECT_MODE" != "all" ]]; then
  echo "--select must be 'first' or 'all'" >&2
  exit 1
fi

CONTEXT_FILE="${CONTRACT_FILE_PATH:?CONTRACT_FILE_PATH env var is required}"
if [[ ! -f "$CONTEXT_FILE" ]]; then
  echo "Context file not found: $CONTEXT_FILE" >&2
  exit 1
fi

REQUESTED_RESOURCES_JSON="${TORQUE_REQUESTED_RESOURCES:-[]}"

if ! jq -e . >/dev/null 2>&1 <<<"$REQUESTED_RESOURCES_JSON"; then
  echo "TORQUE_REQUESTED_RESOURCES must be valid JSON" >&2
  exit 1
fi

if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$REQUESTED_RESOURCES_JSON"; then
  echo "TORQUE_REQUESTED_RESOURCES must be a JSON array" >&2
  exit 1
fi

MATCHED_RESOURCES_JSON="$(
  jq -c \
    --arg rt "$RESOURCE_TYPE" \
    --arg tk "$TAG_KEY" \
    --arg tv "$TAG_VALUE" \
    --arg op "$MATCH_OPERATOR" \
    --arg selectMode "$SELECT_MODE" \
    --argjson requestedResources "$REQUESTED_RESOURCES_JSON" \
    --argjson inactiveOnly "$([[ "$INACTIVE_ONLY" == "true" ]] && echo true || echo false)" \
    --argjson activeOnly "$([[ "$ACTIVE_ONLY" == "true" ]] && echo true || echo false)" \
    '
      def resource_match($r; $resourceFilters):
        if ($resourceFilters | length) == 0 then
          true
        else
          (($r.identifier // "") | tostring) as $rid
          | (($r.grain_path // "") | tostring) as $gpath
          | any(
              $resourceFilters[];
              ((.identifier // "") | tostring) == $rid
              and (
                ((.grain_path // "") | tostring) == ""
                or ((.grain_path // "") | tostring) == $gpath
              )
            )
        end;

      def match_tag($tags; $k; $v; $op):
        if $k == "" then
          true
        else
          ((($tags[$k] // "") | tostring) as $actual
          | if $op == "eq" then ($actual == $v) else ($actual != $v) end)
        end;

      def is_inactive($r):
        (($r.attributes.power_state // $r.attributes.powerState // $r.power_state // $r.powerState // "") | tostring | ascii_downcase) as $power_state
        | if $power_state == "deallocated" then
            true
          else
        (($r.attributes.properties.instanceView.statuses // [])
          | map((.code // .displayStatus // "") | tostring | ascii_downcase)
        ) as $statuses
        | if ($statuses | any(contains("powerstate/stopped") or contains("powerstate/deallocated") or contains("vm stopped") or contains("vm deallocated"))) then
            true
          elif ($statuses | any(contains("powerstate/running") or contains("vm running"))) then
            false
          else
            (($r.attributes.status // $r.attributes.state // $r.status // $r.state // "") | tostring | ascii_downcase) as $s
            | (["inactive", "stopped", "off", "deallocated", "terminated", "stopping"] | index($s)) != null
          end
        end;

      ($rt | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))) as $resourceTypes
      |
      ($requestedResources | map({
          identifier: ((.identifier // "") | tostring),
          grain_path: ((.grain_path // "") | tostring)
        })) as $allowedResources
      |
      (.resources // [])
      | map(
          . as $r
          | (($r.attributes.tags // $r.attributes.Tags // $r.tags // {}) ) as $raw_tags
          | (
              if ($raw_tags | type) == "object" then $raw_tags
              elif ($raw_tags | type) == "string" then (try ($raw_tags | fromjson) catch {})
              else {}
              end
            ) as $tags
          | ($r.type // $r.resource_type // $r.resourceType // "") as $type
          | select(
              ($resourceTypes | index($type)) != null
              and resource_match($r; $allowedResources)
              and match_tag($tags; $tk; $tv; $op)
              and (if $inactiveOnly then is_inactive($r) else true end)
              and (if $activeOnly then (is_inactive($r) | not) else true end)
            )
        )
      | if $selectMode == "first" and (length > 0) then [.[0]] else . end
    ' "$CONTEXT_FILE"
)"

MATCHED_REQUESTED_RESOURCES_JSON="$(
  jq -c '
    map({
      grain_path: ((.grain_path // "") | tostring),
      identifier: ((.identifier // "") | tostring)
    })
    | map(select(.identifier != ""))
  ' <<<"$MATCHED_RESOURCES_JSON"
)"

MATCHED_COUNT="$(jq -r 'length' <<<"$MATCHED_REQUESTED_RESOURCES_JSON")"
if [[ "$MATCHED_COUNT" -eq 0 && "$REQUIRE_MATCH" == "true" ]]; then
  echo "No matching Azure VM found for ${RESOURCE_TYPE} with ${TAG_KEY}=${TAG_VALUE}" >&2
  exit 20
fi

export vms_json="$MATCHED_REQUESTED_RESOURCES_JSON"