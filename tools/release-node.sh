#!/bin/sh
set -eu

node_id="${WARP_INPUT_NODE_ID}"
role="${WARP_INPUT_ROLE}"
release_policy_ref="${WARP_INPUT_RELEASE_POLICY_REF}"

# Output stubs for OpenCHAMI node release
release_attempt_id="release-$(date +%s)"
status_json="{}"

if [ -n "${WARP_OUTPUT:-}" ]; then
  echo "release_attempt_id=${release_attempt_id}" >> "${WARP_OUTPUT}"
  echo "status_json=${status_json}" >> "${WARP_OUTPUT}"
fi
