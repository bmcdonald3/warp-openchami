#!/bin/sh
set -eu

node_id="${WARP_INPUT_NODE_ID}"
role="${WARP_INPUT_ROLE}"
attempt_id="${WARP_INPUT_ATTEMPT_ID}"

# Output stub for OpenCHAMI node verification
status_json="{}"

if [ -n "${WARP_OUTPUT:-}" ]; then
  echo "status_json=${status_json}" >> "${WARP_OUTPUT}"
fi
