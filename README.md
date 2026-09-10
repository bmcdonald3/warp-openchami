# OpenCHAMI Warp Capability

This repository contains the Forge warp capability for OpenCHAMI. It serves as an adapter implementing the `hpe/core-baremetal/baremetal-lifecycle-providers` contract, enabling Forge to orchestrate node lifecycle operations (discovery, inventory, power management, firmware application, provisioning, verification, and release) using OpenCHAMI services.

## Execution Architecture

Warp executes the capabilities defined in `manifest.yaml` using the `executable` runner. The flow operates as follows:

1. A command like `warp run hpe/openchami/power-node --with node_id=node-101 --with action=on` is issued.
2. Warp reads the tool definition in `manifest.yaml` and executes the designated script (e.g., `tools/power-node.sh` or `tools/discover-nodes.sh`).
3. Warp injects the `--with` arguments into the script's environment as uppercase variables prefixed with `WARP_INPUT_` (e.g., `WARP_INPUT_NODE_ID`, `WARP_INPUT_ACTION`).
4. The shell script consumes these environment variables and constructs a direct command to the backend CLI, `magellan` (e.g., `magellan power set --node "$WARP_INPUT_NODE_ID" --action "$WARP_INPUT_ACTION"` or `magellan crawl "$WARP_INPUT_NODE_ID" -i`).
5. The script captures the standard output from `magellan` and appends it as key-value pairs to the temporary file path injected at `$WARP_OUTPUT`. Warp reads this file to return the structured data back to the user.

## Building and Remote Deployment

To test the capability against live nodes, Warp can be built for Linux and deployed to a remote machine:

```bash
# Build the Warp CLI for Linux
GOOS=linux GOARCH=amd64 go build -o warp ./cmd/warp

# Deploy to the remote host
scp warp root@tamarindo.hpc.amslabs.hpecorp.net:/usr/local/bin/

```

## Current Setup and Testing

The `discover-nodes` tool has been successfully tested on the remote machine. It mirrors the underlying command: `magellan crawl <node_id> -i`.

### Remote Execution Steps

```bash
# Initialize the Warp workspace
warp workspace init

# Import the capability from the current directory
warp cap import .

# Install the capability to the workspace
warp workspace install hpe/openchami

# Execute the discover-nodes tool against a BMC
warp run hpe/openchami/discover-nodes --with node_id=https://172.24.0.3 --with master_key=$MASTER_KEY

```

### Expected Output

Successful execution resolves BMC credentials and completes without errors:

```text
Starting tool: hpe/openchami/discover-nodes

Run ID: 90c71ef8-a840-408e-89e0-eee5d52fc520
{"level":"warn","uri":"https://172.24.0.3","time":"2026-09-10T16:10:53-05:00","caller":"/root/mcdonald/magellan/cmd/crawl.go:78","message":"specific credentials not found, falling back to default"}
{"level":"info","uri":"https://172.24.0.3","time":"2026-09-10T16:10:53-05:00","caller":"/root/mcdonald/magellan/cmd/crawl.go:90","message":"default credentials found, using"}
{"level":"info","id":"https://172.24.0.3","time":"2026-09-10T16:10:53-05:00","caller":"/root/mcdonald/magellan/internal/util/bmc.go:43","message":"specific credentials found, using"}
{"level":"info","id":"https://172.24.0.3","time":"2026-09-10T16:11:47-05:00","caller":"/root/mcdonald/magellan/internal/util/bmc.go:43","message":"specific credentials found, using"}
✓ Completed

```
