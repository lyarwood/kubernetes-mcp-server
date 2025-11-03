#!/usr/bin/env bash
# Shared verification helper functions for VirtualMachine tests

# verify_vm_exists: Waits for a VirtualMachine to be created
# Usage: verify_vm_exists <vm-name> <namespace> [timeout]
verify_vm_exists() {
    local vm_name="$1"
    local namespace="$2"
    local timeout="${3:-30s}"

    if ! kubectl wait --for=jsonpath='{.metadata.name}'="$vm_name" virtualmachine/"$vm_name" -n "$namespace" --timeout="$timeout" 2>/dev/null; then
        echo "VirtualMachine $vm_name not found in namespace $namespace"
        kubectl get virtualmachines -n "$namespace"
        return 1
    fi
    echo "VirtualMachine $vm_name created successfully"
    return 0
}

# verify_container_disk: Verifies that a VM uses a specific container disk OS
# Usage: verify_container_disk <vm-name> <namespace> <os-name>
# Example: verify_container_disk test-vm vm-test fedora
verify_container_disk() {
    local vm_name="$1"
    local namespace="$2"
    local os_name="$3"

    # Get all container disk images from all volumes
    local container_disks
    container_disks=$(kubectl get virtualmachine "$vm_name" -n "$namespace" -o jsonpath='{.spec.template.spec.volumes[*].containerDisk.image}')

    if [[ "$container_disks" =~ $os_name ]]; then
        echo "✓ VirtualMachine uses $os_name container disk"
        return 0
    else
        echo "✗ Expected $os_name container disk, found volumes with images: $container_disks"
        kubectl get virtualmachine "$vm_name" -n "$namespace" -o yaml
        return 1
    fi
}

# verify_run_strategy: Verifies that runStrategy is set (in spec or status)
# Usage: verify_run_strategy <vm-name> <namespace>
verify_run_strategy() {
    local vm_name="$1"
    local namespace="$2"

    local spec_run_strategy
    local status_run_strategy
    spec_run_strategy=$(kubectl get virtualmachine "$vm_name" -n "$namespace" -o jsonpath='{.spec.runStrategy}')
    status_run_strategy=$(kubectl get virtualmachine "$vm_name" -n "$namespace" -o jsonpath='{.status.runStrategy}')

    if [[ -n "$spec_run_strategy" ]]; then
        echo "✓ VirtualMachine uses runStrategy in spec: $spec_run_strategy"
        return 0
    elif [[ -n "$status_run_strategy" ]]; then
        echo "✓ VirtualMachine has runStrategy in status: $status_run_strategy"
        echo "  Note: VM may have been created with deprecated 'running' field, but runStrategy is set in status"
        return 0
    else
        echo "✗ VirtualMachine missing runStrategy field in both spec and status"
        return 1
    fi
}

# verify_no_deprecated_running_field: Verifies that deprecated 'running' field is NOT set
# Usage: verify_no_deprecated_running_field <vm-name> <namespace>
verify_no_deprecated_running_field() {
    local vm_name="$1"
    local namespace="$2"

    local running_field
    running_field=$(kubectl get virtualmachine "$vm_name" -n "$namespace" -o jsonpath='{.spec.running}')

    if [[ -z "$running_field" ]]; then
        echo "✓ VirtualMachine does not use deprecated 'running' field"
        return 0
    else
        echo "✗ VirtualMachine uses deprecated 'running' field with value: $running_field"
        echo "  Please use 'runStrategy' instead of 'running'"
        kubectl get virtualmachine "$vm_name" -n "$namespace" -o yaml
        return 1
    fi
}

# verify_instancetype: Verifies that a VM has an instancetype reference
# Usage: verify_instancetype <vm-name> <namespace> [expected-instancetype] [expected-kind]
verify_instancetype() {
    local vm_name="$1"
    local namespace="$2"
    local expected_instancetype="$3"
    local expected_kind="${4:-VirtualMachineClusterInstancetype}"

    local instancetype
    instancetype=$(kubectl get virtualmachine "$vm_name" -n "$namespace" -o jsonpath='{.spec.instancetype.name}')

    if [[ -z "$instancetype" ]]; then
        echo "✗ VirtualMachine has no instancetype reference"
        return 1
    fi

    echo "✓ VirtualMachine has instancetype reference: $instancetype"

    # Check expected instancetype if provided
    if [[ -n "$expected_instancetype" ]]; then
        if [[ "$instancetype" == "$expected_instancetype" ]]; then
            echo "✓ Instancetype matches expected value: $expected_instancetype"
        else
            echo "✗ Expected instancetype '$expected_instancetype', found: $instancetype"
            return 1
        fi
    fi

    # Verify instancetype kind
    local instancetype_kind
    instancetype_kind=$(kubectl get virtualmachine "$vm_name" -n "$namespace" -o jsonpath='{.spec.instancetype.kind}')
    if [[ "$instancetype_kind" == "$expected_kind" ]]; then
        echo "✓ Instancetype kind is $expected_kind"
    else
        echo "⚠ Instancetype kind is: $instancetype_kind (expected: $expected_kind)"
    fi

    return 0
}

# verify_instancetype_contains: Verifies that instancetype name contains a string
# Usage: verify_instancetype_contains <vm-name> <namespace> <substring> [description]
verify_instancetype_contains() {
    local vm_name="$1"
    local namespace="$2"
    local substring="$3"
    local description="${4:-$substring}"

    local instancetype
    instancetype=$(kubectl get virtualmachine "$vm_name" -n "$namespace" -o jsonpath='{.spec.instancetype.name}')

    if [[ -z "$instancetype" ]]; then
        echo "✗ VirtualMachine has no instancetype reference"
        return 1
    fi

    if [[ "$instancetype" =~ $substring ]]; then
        echo "✓ Instancetype matches $description: $instancetype"
        return 0
    else
        echo "⚠ Instancetype '$instancetype' doesn't match $description"
        return 0  # Return success for warnings
    fi
}

# verify_instancetype_prefix: Verifies that instancetype starts with a prefix
# Usage: verify_instancetype_prefix <vm-name> <namespace> <prefix> [description]
verify_instancetype_prefix() {
    local vm_name="$1"
    local namespace="$2"
    local prefix="$3"
    local description="${4:-$prefix}"

    local instancetype
    instancetype=$(kubectl get virtualmachine "$vm_name" -n "$namespace" -o jsonpath='{.spec.instancetype.name}')

    if [[ -z "$instancetype" ]]; then
        echo "✗ VirtualMachine has no instancetype reference"
        return 1
    fi

    if [[ "$instancetype" =~ ^${prefix}\. ]]; then
        echo "✓ Instancetype matches $description family: $instancetype"
        return 0
    else
        echo "⚠ Instancetype '$instancetype' doesn't start with '$prefix'"
        return 0  # Return success for warnings
    fi
}

# verify_no_direct_resources: Verifies VM uses instancetype (no direct memory spec)
# Usage: verify_no_direct_resources <vm-name> <namespace>
verify_no_direct_resources() {
    local vm_name="$1"
    local namespace="$2"

    local guest_memory
    guest_memory=$(kubectl get virtualmachine "$vm_name" -n "$namespace" -o jsonpath='{.spec.template.spec.domain.memory.guest}')

    if [[ -z "$guest_memory" ]]; then
        echo "✓ VirtualMachine uses instancetype for resources (no direct memory spec)"
        return 0
    else
        echo "⚠ VirtualMachine has direct memory specification: $guest_memory"
        return 0  # Return success for warnings
    fi
}

# verify_has_resources_or_instancetype: Verifies VM has either instancetype or direct resources
# Usage: verify_has_resources_or_instancetype <vm-name> <namespace>
verify_has_resources_or_instancetype() {
    local vm_name="$1"
    local namespace="$2"

    local instancetype
    instancetype=$(kubectl get virtualmachine "$vm_name" -n "$namespace" -o jsonpath='{.spec.instancetype.name}')

    if [[ -n "$instancetype" ]]; then
        echo "✓ VirtualMachine has instancetype reference: $instancetype"
        return 0
    fi

    # Check for direct resource specification
    local guest_memory
    guest_memory=$(kubectl get virtualmachine "$vm_name" -n "$namespace" -o jsonpath='{.spec.template.spec.domain.memory.guest}')

    if [[ -n "$guest_memory" ]]; then
        echo "⚠ No instancetype set, but VM has direct memory specification: $guest_memory"
        return 0
    else
        echo "✗ VirtualMachine has no instancetype and no direct resource specification"
        kubectl get virtualmachine "$vm_name" -n "$namespace" -o yaml
        return 1
    fi
}
