#!/bin/sh
set -eu

node_id="${WARP_INPUT_NODE_ID}"
# The inventory_policy_ref is available here if it needs to be mapped to a future magellan configuration file or flag.
policy_ref="${WARP_INPUT_INVENTORY_POLICY_REF}"

# Pass the node_id into collect using the --data flag, outputting JSON to standard out
inventory_snapshot=$(magellan collect --data "${node_id}" --output-format json --show-output)

if [ -n "${WARP_OUTPUT:-}" ]; then
  cat <<EOF >> "${WARP_OUTPUT}"
inventory_snapshot<<DELIMITER
${inventory_snapshot}
DELIMITER
EOF
fi
