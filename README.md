# OpenCHAMI Warp Capability

This repository contains the Forge warp capability for OpenCHAMI. It serves as an adapter implementing the `hpe/core-baremetal/baremetal-lifecycle-providers` contract, enabling Forge to orchestrate node lifecycle operations (discovery, inventory, power management, firmware application, provisioning, verification, and release) using OpenCHAMI services.

## Execution Architecture

Warp executes the capabilities defined in `manifest.yaml` using the `executable` runner. The flow operates as follows:
1. A command like `warp run hpe/openchami/power-node --with node_id=node-101 --with action=on` is issued.
2. Warp reads the tool definition in `manifest.yaml` and executes the designated script (e.g., `tools/power-node.sh`).
3. Warp injects the `--with` arguments into the script's environment as uppercase variables prefixed with `WARP_INPUT_` (e.g., `WARP_INPUT_NODE_ID`, `WARP_INPUT_ACTION`).
4. The shell script consumes these environment variables and constructs a direct command to the backend CLI, `magellan` (e.g., `magellan power set --node "$WARP_INPUT_NODE_ID" --action "$WARP_INPUT_ACTION"`).
5. The script captures the standard output from `magellan` and appends it as key-value pairs to the temporary file path injected at `$WARP_OUTPUT`. Warp reads this file to return the structured data back to the user.

## Current Setup Steps Completed

The following commands have been run to bootstrap the first iteration of this capability:

```bash
# Create the capability structure
warp cap create openchami --namespace hpe
cd openchami
mkdir tools

# (manifest.yaml and tools/power-node.sh were manually populated)

# Grant execution permissions to the wrapper script
chmod +x tools/power-node.sh

# Import the capability into the local catalog
cd ..
warp cap import openchami
```

## Known Issues

When testing the `power-node` capability, the execution fails with an exit code 2 and the following standard error output:

```text
Starting tool: hpe/openchami/power-node

Run ID: 84c2d6b7-dd1c-485b-8046-7f4558ba66da
panic: unable to redefine 'l' shorthand in "power" flagset: it's already used for "list-reset-types" flag

goroutine 1 [running]:
github.com/spf13/pflag.(*FlagSet).AddFlag(0x5583b2da4800, 0x5583b2daba40)
        /Users/benmcdonald/go/pkg/mod/github.com/spf13/pflag@v1.0.10/flag.go:904 +0x330
...
github.com/OpenCHAMI/magellan/cmd.Execute()
        /Users/benmcdonald/magellan/cmd/root.go:84 +0x24
main.main()
        /Users/benmcdonald/magellan/main.go:8 +0x1c
```

### Diagnosis
This error originates directly from the upstream `magellan` CLI binary. The Go runtime panic indicates a conflict within the `github.com/spf13/pflag` library utilized by Magellan's command parser (Cobra). Specifically, two different flags within the `power` command subset are attempting to claim the `-l` shorthand character (one being `list-reset-types`). 

Because Warp successfully initiated the tool and captured the runtime panic from Magellan, the integration between Warp and the wrapper script is confirmed functional. To resume work, the `power-node.sh` wrapper script can be temporarily pointed at a different, working `magellan` command, or the upstream `magellan` binary will need to be patched to resolve the flag collision.
