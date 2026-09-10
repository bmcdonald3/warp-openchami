#!/bin/sh
set -eu

node_id="${WARP_INPUT_NODE_ID}"
role="${WARP_INPUT_ROLE}"
image_ref="${WARP_INPUT_IMAGE_REF}"
network_attachment_ref="${WARP_INPUT_NETWORK_ATTACHMENT_REF}"

# Output stubs for OpenCHAMI BSS provisioning
attempt_id="attempt-$(date +%s)"
lifecycle_attempt="{}"

if [ -n "${WARP_OUTPUT:-}" ]; then
  echo "attempt_id=${attempt_id}" >> "${WARP_OUTPUT}"
  echo "lifecycle_attempt=${lifecycle_attempt}" >> "${WARP_OUTPUT}"
fi
