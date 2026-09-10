#!/bin/sh
set -eu

node_id="${WARP_INPUT_NODE_ID}"
firmware_policy_ref="${WARP_INPUT_FIRMWARE_POLICY_REF}"

# Dispatch the firmware update
magellan update "${node_id}" --firmware-uri "${firmware_policy_ref}"

# Retrieve the status of the update to return to the warp contract
firmware_status=$(magellan update "${node_id}" --status)

if [ -n "${WARP_OUTPUT:-}" ]; then
  echo "firmware_status=${firmware_status}" >> "${WARP_OUTPUT}"
fi
