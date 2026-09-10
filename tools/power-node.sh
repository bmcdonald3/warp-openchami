#!/bin/sh
set -eu

# 1. Read injected inputs
node_id="${WARP_INPUT_NODE_ID}"
action="${WARP_INPUT_ACTION}"

# 2. Execute magellan CLI using the inputs
# (Assuming magellan outputs a JSON status string)
magellan_output=$(magellan power "${node_id}" -r "${action}")

# 3. Write the required 'power_status' output to the WARP_OUTPUT path
if [ -n "${WARP_OUTPUT:-}" ]; then
  echo "power_status=${magellan_output}" >> "${WARP_OUTPUT}"
fi
