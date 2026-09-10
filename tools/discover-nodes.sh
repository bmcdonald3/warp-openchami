#!/bin/sh
set -eu

node_id="${WARP_INPUT_NODE_ID}"

# Crawl the specific node and format the output as JSON
node_inventory=$(magellan crawl "${node_id}" --output-format json)

if [ -n "${WARP_OUTPUT:-}" ]; then
  # Heredoc format is used to handle multi-line JSON output safely
  cat <<EOF >> "${WARP_OUTPUT}"
node_inventory<<DELIMITER
${node_inventory}
DELIMITER
EOF
fi
