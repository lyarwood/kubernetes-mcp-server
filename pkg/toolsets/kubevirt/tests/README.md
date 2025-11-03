# KubeVirt VM Toolset Tests

This directory contains gevals-based tests for the KubeVirt VM toolset in the Kubernetes MCP Server.

## Overview

These tests validate the VM creation and troubleshooting tools (`vm_create` and `vm_troubleshoot`) by having AI agents complete real tasks using the MCP server.

## Test Structure

```
tests/
├── README.md                          # This file
├── mcp-config.yaml                    # MCP server configuration
├── claude-code/                       # Claude Code agent configuration
│   ├── agent.yaml
│   └── eval.yaml
└── tasks/                             # Test tasks
    ├── create-vm-basic/               # Basic VM creation test
    ├── create-vm-with-instancetype/   # VM with specific instancetype
    ├── create-vm-with-size/           # VM with size parameter
    ├── create-vm-ubuntu/              # Ubuntu VM creation
    ├── create-vm-with-performance/    # VM with performance family
    └── troubleshoot-vm/               # VM troubleshooting test
```

## Prerequisites

1. **Kubernetes cluster** with KubeVirt installed
   - The cluster must have KubeVirt CRDs installed
   - For testing, you can use a Kind cluster with KubeVirt

2. **Kubernetes MCP Server** running at `http://localhost:8888/mcp`

   ```bash
   # Build and run the server
   cd /path/to/kubernetes-mcp-server
   make build
   ./kubernetes-mcp-server --port 8888
   ```

3. **gevals binary** built from the gevals project

   ```bash
   cd /path/to/gevals
   go build -o gevals ./cmd/gevals
   ```

4. **Claude Code** installed and in PATH

   ```bash
   # Install Claude Code (if not already installed)
   npm install -g @anthropicsdk/claude-code
   ```

5. **kubectl** configured to access your cluster

## Running the Tests

### Run All Tests

```bash
# From the gevals directory
./gevals eval /path/to/kubernetes-mcp-server/pkg/toolsets/kubevirt/vm/tests/claude-code/eval.yaml
```

### Run a Specific Test

```bash
# Run just the basic VM creation test
./gevals eval /path/to/kubernetes-mcp-server/pkg/toolsets/kubevirt/vm/tests/tasks/create-vm-basic/create-vm-basic.yaml \
  --agent-file /path/to/kubernetes-mcp-server/pkg/toolsets/kubevirt/vm/tests/claude-code/agent.yaml \
  --mcp-config-file /path/to/kubernetes-mcp-server/pkg/toolsets/kubevirt/vm/tests/mcp-config.yaml
```

## Test Descriptions

### create-vm-basic

**Difficulty:** Easy
**Description:** Tests basic VM creation with default Fedora workload.
**Key Tool:** `vm_create`
**Expected Behavior:** Agent should use `vm_create` to generate a plan and then create the VM using `resources_create_or_update`.

### create-vm-with-instancetype

**Difficulty:** Medium
**Description:** Tests VM creation with a specific instancetype (u1.medium).
**Key Tool:** `vm_create`
**Expected Behavior:** Agent should pass the instancetype parameter to `vm_create` and create a VM with the correct instancetype reference.

### create-vm-with-size

**Difficulty:** Medium
**Description:** Tests VM creation using a size hint ('large').
**Key Tool:** `vm_create`
**Expected Behavior:** Agent should use the size parameter which should map to an appropriate instancetype.

### create-vm-ubuntu

**Difficulty:** Easy
**Description:** Tests VM creation with Ubuntu workload.
**Key Tool:** `vm_create`
**Expected Behavior:** Agent should create a VM using the Ubuntu container disk image.

### create-vm-with-performance

**Difficulty:** Medium
**Description:** Tests VM creation with performance family ('compute-optimized') and size.
**Key Tool:** `vm_create`
**Expected Behavior:** Agent should combine performance and size to select an appropriate instancetype (e.g., c1.medium).

### troubleshoot-vm

**Difficulty:** Easy
**Description:** Tests VM troubleshooting guide generation.
**Key Tool:** `vm_troubleshoot`
**Expected Behavior:** Agent should use `vm_troubleshoot` to generate a troubleshooting guide for the VM.

## Assertions

The tests validate:

- **Tool Usage:** Agents must call `vm_create`, `vm_troubleshoot`, or `resources_*` tools
- **Call Limits:** Between 1 and 30 tool calls (allows for exploration and creation)
- **Task Success:** Verification scripts confirm VMs are created correctly

## Expected Results

**✅ Pass** means:

- The VM tools are well-designed and discoverable
- Tool descriptions are clear to AI agents
- Schemas are properly structured
- Implementation works correctly

**❌ Fail** indicates:

- Tool descriptions may need improvement
- Schema complexity issues
- Missing functionality
- Implementation bugs

## Output

Results are saved to `gevals-kubevirt-vm-operations-out.json` with:

- Task pass/fail status
- Assertion results
- Tool call history
- Agent interactions

## Customization

### Using Different AI Agents

You can create additional agent configurations (similar to the `claude-code/` directory) for testing with different AI models:

```yaml
# Example: openai-agent/agent.yaml
kind: Agent
metadata:
  name: "openai-agent"
commands:
  argTemplateMcpServer: "{{ .File }}"
  runPrompt: |-
    agent-wrapper.sh {{ .McpServerFileArgs }} "{{ .Prompt }}"
```

### Adding New Tests

To add a new test task:

1. Create a new directory under `tasks/`
2. Add task YAML file with prompt
3. Add setup, verify, and cleanup scripts
4. The test will be automatically discovered by the glob pattern in `eval.yaml`

## Troubleshooting

### Tests Fail to Connect to MCP Server

Ensure the Kubernetes MCP Server is running:

```bash
curl http://localhost:8888/mcp/health
```

### VirtualMachine Not Created

Check if KubeVirt is installed:

```bash
kubectl get crds | grep kubevirt
kubectl get pods -n kubevirt
```

### Permission Issues

Ensure your kubeconfig has permissions to:

- Create namespaces
- Create VirtualMachine resources
- List instancetypes and preferences

## Contributing

When adding new tests:

- Keep tasks focused on a single capability
- Make verification scripts robust
- Document expected behavior
- Set appropriate difficulty levels
- Ensure cleanup scripts remove all resources
