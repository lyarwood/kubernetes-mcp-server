#!/usr/bin/env bash
# Script to run gevals against agent and model combinations
# Usage: ./run-agent-model-evals.sh -a AGENT/MODEL [-a AGENT2/MODEL2 ...] [options]
#
# This script works with ANY agent type and model name combination.
# Just specify the agent/model pairs you want to evaluate.

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Source the model configuration
source "$SCRIPT_DIR/model-configs.sh"

# Default values
OUTPUT_DIR="$SCRIPT_DIR/results"
OUTPUT_PREFIX=""
VERBOSE=false
DRY_RUN=false
VALIDATE_KEYS_ONLY=false
CHECK_API=false
PARALLEL=false
MAX_PARALLEL_JOBS=0
AGENT_MODEL_COMBINATIONS=()

# Available agent types
AVAILABLE_AGENTS=("openai-agent" "gemini" "claude-code")

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            cat <<EOF
Usage: $0 -a AGENT[/MODEL] [-a AGENT2[/MODEL2] ...] [options]

Run gevals against one or more agent and model combinations.

This script works with ANY agent type and model name combination.
Specify agent/model pairs using the format: -a agent-type/model-name
For agents with pre-configured models (gemini, claude-code), the model is optional: -a agent-type

Available agent types: ${AVAILABLE_AGENTS[*]}

Options:
  -h, --help                Show this help message
  -a, --agent AGENT[/MODEL] Specify an agent or agent/model combination (can be used multiple times)
                            Format: agent-type or agent-type/model-name
  -o, --output-dir DIR      Directory to store results (default: ./results)
  -p, --prefix PREFIX       Prefix for output files (default: none)
  -v, --verbose             Enable verbose output
  --dry-run                 Print commands without executing them
  --validate-secrets        Only validate that model secrets are available
  --check-api               Validate API endpoints are OpenAI-compatible (with --validate-secrets)
  --parallel                Run evaluations in parallel (each gets unique namespace)
  -j, --jobs N              Maximum number of parallel jobs (default: number of combinations)

Examples:
  # Run evaluation with agent+model combination (openai-agent requires model)
  $0 -a openai-agent/gemini-2.0-flash

  # Run evaluation with agent only (for agents with pre-configured models)
  $0 -a gemini -a claude-code

  # Run evaluations for multiple combinations
  $0 -a openai-agent/gemini-2.0-flash -a openai-agent/claude-sonnet-4@20250514

  # Test one model across multiple agents (mix of agent-only and agent/model)
  $0 -a openai-agent/gemini-2.0-flash -a gemini -a claude-code

  # Run with custom output prefix
  $0 -a openai-agent/gemini-2.0-flash -p "experiment-1"

  # Run multiple combinations in parallel (each gets unique namespace)
  $0 -a openai-agent/gemini-2.0-flash -a gemini -a claude-code --parallel

  # Limit parallel jobs to 2 at a time
  $0 -a openai-agent/gemini-2.0-flash -a gemini --parallel -j 2

  # Validate secrets for models used in combinations
  $0 -a openai-agent/gemini-2.0-flash -a openai-agent/claude-sonnet-4@20250514 --validate-secrets

  # Validate secrets AND check API endpoint connectivity
  $0 -a openai-agent/gemini-2.0-flash --validate-secrets --check-api
EOF
            exit 0
            ;;
        -a|--agent)
            AGENT_MODEL_COMBINATIONS+=("$2")
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -p|--prefix)
            OUTPUT_PREFIX="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --validate-secrets|--validate-keys)
            VALIDATE_KEYS_ONLY=true
            shift
            ;;
        --check-api)
            CHECK_API=true
            shift
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        -j|--jobs)
            MAX_PARALLEL_JOBS="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option $1" >&2
            echo "Run '$0 --help' for usage information" >&2
            exit 1
            ;;
    esac
done

# Check if at least one combination was specified
if [ ${#AGENT_MODEL_COMBINATIONS[@]} -eq 0 ]; then
    echo "Error: No agent/model combinations specified. Use -a to specify at least one." >&2
    echo "Example: $0 -a openai-agent/gemini-2.0-flash" >&2
    echo "Run '$0 --help' for usage information" >&2
    exit 1
fi

# Parse and validate combinations
declare -a AGENTS
declare -a MODELS
declare -a UNIQUE_MODELS

for combination in "${AGENT_MODEL_COMBINATIONS[@]}"; do
    # Split on '/' to get agent and model (model is optional)
    if [[ "$combination" =~ / ]]; then
        # Format: agent/model
        agent="${combination%%/*}"
        model="${combination#*/}"
    else
        # Format: agent (no model specified)
        agent="$combination"
        model=""
    fi

    # Validate agent type exists
    if [[ ! " ${AVAILABLE_AGENTS[*]} " =~ " ${agent} " ]]; then
        echo "Error: Unknown agent type '$agent' in combination '$combination'" >&2
        echo "Available agents: ${AVAILABLE_AGENTS[*]}" >&2
        exit 1
    fi

    # Store the pair
    AGENTS+=("$agent")
    MODELS+=("$model")

    # Build unique models list for validation (only if model is specified)
    if [ -n "$model" ]; then
        # Check if model is already in the list
        found=false
        for existing in "${UNIQUE_MODELS[@]+"${UNIQUE_MODELS[@]}"}"; do
            if [ "$existing" = "$model" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            UNIQUE_MODELS+=("$model")
        fi
    fi
done

# Validate model secrets (only if any models were specified)
# Use a nounset-safe check for array length
set +u
unique_model_count=${#UNIQUE_MODELS[@]}
set -u
if [ "$unique_model_count" -gt 0 ]; then
    # Build validation command with optional --check-api flag
    if [ "$CHECK_API" = true ]; then
        validate_cmd=(validate_model_secrets --check-api "${UNIQUE_MODELS[@]}")
    else
        validate_cmd=(validate_model_secrets "${UNIQUE_MODELS[@]}")
    fi

    if ! "${validate_cmd[@]}"; then
        echo ""
        echo "Some model secrets are missing from gnome-keyring."
        echo "Each model requires both an api-key and a base-url to be stored."
        echo ""
        echo "Example: To configure a model, determine its normalized service name:"
        echo "  source model-configs.sh"
        echo "  normalize_model_name \"your-model-name\""
        echo ""
        echo "Then store the secrets using the service name:"
        echo "  secret-tool store --label='Model API Key' service model-{normalized-name} account api-key"
        echo "  secret-tool store --label='Model Base URL' service model-{normalized-name} account base-url"
        echo ""
        echo "See EVAL_README.md for detailed setup instructions."
        echo ""
        if [ "$VALIDATE_KEYS_ONLY" = true ]; then
            exit 1
        fi
    fi
else
    echo "Note: No models specified for validation (agents without models specified)" >&2
fi

if [ "$VALIDATE_KEYS_ONLY" = true ]; then
    exit 0
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Log file for the entire run
RUN_LOG="$OUTPUT_DIR/gevals-run-$(date +%Y%m%d-%H%M%S).log"
echo "Logging to: $RUN_LOG"

# Record start time for filtering results later
RUN_START_TIME=$(date +%s)

# Summary variables
TOTAL_COMBINATIONS=${#AGENT_MODEL_COMBINATIONS[@]}
SUCCESS_COUNT=0
FAILURE_COUNT=0
SKIPPED_COUNT=0

echo "========================================" | tee -a "$RUN_LOG"
echo "Starting evaluation run" | tee -a "$RUN_LOG"
echo "Date: $(date)" | tee -a "$RUN_LOG"
echo "Combinations: ${AGENT_MODEL_COMBINATIONS[*]}" | tee -a "$RUN_LOG"
echo "Total combinations: $TOTAL_COMBINATIONS" | tee -a "$RUN_LOG"
echo "Output directory: $OUTPUT_DIR" | tee -a "$RUN_LOG"
echo "========================================" | tee -a "$RUN_LOG"
echo "" | tee -a "$RUN_LOG"

# Function to get the eval name from eval.yaml
get_eval_name() {
    local agent_type="$1"
    local eval_file="$SCRIPT_DIR/$agent_type/eval.yaml"

    if [ ! -f "$eval_file" ]; then
        echo "ERROR: eval.yaml not found at $eval_file" >&2
        return 1
    fi

    # Extract the name from the metadata section
    local eval_name=$(grep -A 1 "^metadata:" "$eval_file" | grep "name:" | sed 's/.*name: *"\?\([^"]*\)"\?.*/\1/')

    if [ -z "$eval_name" ]; then
        echo "ERROR: Could not extract eval name from $eval_file" >&2
        return 1
    fi

    echo "$eval_name"
}

# Function to run evaluation for a single agent+model combination
run_eval() {
    local agent_type="$1"
    local model_name="$2"
    local eval_namespace="${3:-vm-test}"  # Default to vm-test if not provided
    local agent_slug=$(echo "$agent_type" | sed 's/[^a-zA-Z0-9._-]/_/g')
    local timestamp=$(date +%Y%m%d-%H%M%S)

    # Build log prefix for this combination (timestamp will be added per message)
    local log_prefix
    if [ -n "$model_name" ]; then
        log_prefix="[$agent_type/$model_name]"
    else
        log_prefix="[$agent_type]"
    fi

    # Helper function to print with timestamp
    log_msg() {
        local timestamp=$(date '+%H:%M:%S')
        echo "[$timestamp] $log_prefix $1"
    }

    # Build filename based on whether model is specified
    local result_file
    if [ -n "$model_name" ]; then
        local model_slug=$(echo "$model_name" | sed 's/[^a-zA-Z0-9._-]/_/g')
        result_file="$OUTPUT_DIR/gevals-${agent_slug}-${model_slug}-${timestamp}.log"
    else
        result_file="$OUTPUT_DIR/gevals-${agent_slug}-${timestamp}.log"
    fi

    log_msg "Result file: $result_file" | tee -a "$RUN_LOG"

    # Get model configuration (only if model is specified)
    local model_base_url model_key model_name_value
    if [ -n "$model_name" ]; then
        local config_output
        if ! config_output=$(get_model_config "$model_name"); then
            log_msg "ERROR: Failed to get configuration for $model_name" | tee -a "$RUN_LOG"
            echo "ERROR: Failed to get configuration for $model_name" >> "$result_file"
            log_msg "Skipping..." | tee -a "$RUN_LOG"
            ((SKIPPED_COUNT++))
            return 1
        fi

        # Parse configuration
        while IFS='=' read -r key value; do
            case "$key" in
                MODEL_BASE_URL) model_base_url="$value" ;;
                MODEL_KEY) model_key="$value" ;;
                MODEL_NAME) model_name_value="$value" ;;
            esac
        done <<< "$config_output"

        # Validate that we have all required values
        if [ -z "$model_base_url" ] || [ -z "$model_key" ] || [ -z "$model_name_value" ]; then
            log_msg "ERROR: Missing required configuration for $model_name" | tee -a "$RUN_LOG"
            echo "ERROR: Missing required configuration for $model_name" >> "$result_file"
            log_msg "Skipping..." | tee -a "$RUN_LOG"
            ((SKIPPED_COUNT++))
            return 1
        fi

        if [ -z "$model_key" ] || [ "$model_key" = "null" ]; then
            log_msg "ERROR: API key not available for $model_name" | tee -a "$RUN_LOG"
            echo "ERROR: API key not available for $model_name" >> "$result_file"
            log_msg "Skipping..." | tee -a "$RUN_LOG"
            ((SKIPPED_COUNT++))
            return 1
        fi
    fi

    # Get eval name for this agent
    local eval_name
    if ! eval_name=$(get_eval_name "$agent_type"); then
        log_msg "ERROR: Failed to get eval name for $agent_type" | tee -a "$RUN_LOG"
        echo "ERROR: Failed to get eval name for $agent_type" >> "$result_file"
        log_msg "Skipping..." | tee -a "$RUN_LOG"
        ((SKIPPED_COUNT++))
        return 1
    fi

    # Construct the command
    local cmd=(
        "gevals" "run"
        "$SCRIPT_DIR/$agent_type/eval.yaml"
    )

    # Export namespace environment variable
    export EVAL_NAMESPACE="$eval_namespace"

    # Export environment variables for this model (only if model is specified)
    if [ -n "$model_name" ]; then
        export MODEL_BASE_URL="$model_base_url"
        export MODEL_KEY="$model_key"
        export MODEL_NAME="$model_name_value"

        if [ "$VERBOSE" = true ]; then
            log_msg "Environment:" | tee -a "$RUN_LOG"
            log_msg "  EVAL_NAMESPACE=$EVAL_NAMESPACE" | tee -a "$RUN_LOG"
            log_msg "  MODEL_BASE_URL=$MODEL_BASE_URL" | tee -a "$RUN_LOG"
            log_msg "  MODEL_NAME=$MODEL_NAME" | tee -a "$RUN_LOG"
            log_msg "  MODEL_KEY=***" | tee -a "$RUN_LOG"
        fi
    else
        # Clear MODEL_* variables if previously set
        unset MODEL_BASE_URL MODEL_KEY MODEL_NAME

        if [ "$VERBOSE" = true ]; then
            log_msg "Environment:" | tee -a "$RUN_LOG"
            log_msg "  EVAL_NAMESPACE=$EVAL_NAMESPACE" | tee -a "$RUN_LOG"
            log_msg "  (using agent-configured model)" | tee -a "$RUN_LOG"
        fi
    fi

    log_msg "Command: ${cmd[*]}" | tee -a "$RUN_LOG"

    if [ "$DRY_RUN" = true ]; then
        log_msg "[DRY RUN] Would execute command" | tee -a "$RUN_LOG"
        return 0
    fi

    # Run the evaluation
    local start_time=$(date +%s)
    local start_time_human=$(date)
    log_msg "Starting evaluation at $start_time_human..." | tee -a "$RUN_LOG"
    echo "Starting evaluation at $start_time_human..." >> "$result_file"
    echo "" >> "$result_file"

    if cd "$PROJECT_ROOT" && "${cmd[@]}" >> "$result_file" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))

        echo "" >> "$result_file"

        # Check for JSON output file (uses eval name from eval.yaml)
        local default_json="gevals-${eval_name}-out.json"
        local default_view_log="gevals-${eval_name}-out.log"

        # Check test results in JSON file
        local test_failed=false
        if [ -f "$default_json" ]; then
            # Check if any tasks failed or had errors
            # Look for "status": "error" or "status": "fail" in the JSON
            if grep -q '"status"[[:space:]]*:[[:space:]]*"\(error\|fail\)"' "$default_json"; then
                test_failed=true
            fi
        fi

        if [ "$test_failed" = true ]; then
            log_msg "FAILURE: Tests failed" | tee -a "$RUN_LOG"
            echo "FAILURE: Tests failed" >> "$result_file"
        else
            log_msg "SUCCESS: All tests passed" | tee -a "$RUN_LOG"
            echo "SUCCESS: All tests passed" >> "$result_file"
        fi
        log_msg "Duration: ${minutes}m ${seconds}s (${duration}s total)" | tee -a "$RUN_LOG"
        echo "Duration: ${minutes}m ${seconds}s (${duration}s total)" >> "$result_file"

        # Process and move gevals output files
        local results_dir="$SCRIPT_DIR/results"
        mkdir -p "$results_dir"

        if [ -f "$default_json" ]; then
            # Generate view output from JSON using gevals view
            log_msg "Generating view output from JSON..." | tee -a "$RUN_LOG"
            echo "Generating view output from JSON..." >> "$result_file"
            if gevals view "$default_json" > "$default_view_log" 2>&1; then
                log_msg "View output generation successful" | tee -a "$RUN_LOG"
                echo "View output generation successful" >> "$result_file"
            else
                log_msg "Warning: Failed to generate view output from JSON" | tee -a "$RUN_LOG"
                echo "Warning: Failed to generate view output from JSON" >> "$result_file"
            fi

            # Move and rename JSON output file
            # Build the output filename with optional prefix, agent type, model (if provided), and timestamp
            local filename_base="gevals-"
            if [ -n "$OUTPUT_PREFIX" ]; then
                filename_base="${filename_base}${OUTPUT_PREFIX}-"
            fi
            filename_base="${filename_base}${agent_slug}-"
            if [ -n "$model_name" ]; then
                filename_base="${filename_base}${model_slug}-"
            fi
            filename_base="${filename_base}${timestamp}-out"

            # Move JSON file
            if [ -f "$default_json" ]; then
                local new_json="$results_dir/${filename_base}.json"
                mv "$default_json" "$new_json"
                log_msg "Moved output file to: $new_json" | tee -a "$RUN_LOG"
                echo "Moved output file to: $new_json" >> "$result_file"
            fi

            # Move view log file
            if [ -f "$default_view_log" ]; then
                local new_view_log="$results_dir/${filename_base}.log"
                mv "$default_view_log" "$new_view_log"
                log_msg "Moved view output to: $new_view_log" | tee -a "$RUN_LOG"
                echo "Moved view output to: $new_view_log" >> "$result_file"
            fi
        else
            log_msg "Warning: JSON output file not found at $default_json" | tee -a "$RUN_LOG"
            echo "Warning: JSON output file not found at $default_json" >> "$result_file"
        fi

        # Update counters based on test results
        if [ "$test_failed" = true ]; then
            ((FAILURE_COUNT++))
            return 1
        else
            ((SUCCESS_COUNT++))
            return 0
        fi
    else
        local exit_code=$?
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))

        log_msg "FAILURE: Evaluation failed (exit code: $exit_code)" | tee -a "$RUN_LOG"
        echo "FAILURE: Evaluation failed (exit code: $exit_code)" >> "$result_file"
        log_msg "Duration: ${minutes}m ${seconds}s (${duration}s total)" | tee -a "$RUN_LOG"
        echo "Duration: ${minutes}m ${seconds}s (${duration}s total)" >> "$result_file"
        ((FAILURE_COUNT++))
        return 1
    fi
}

# Function to generate unique namespace
generate_unique_namespace() {
    local agent_type="$1"
    local model_name="$2"

    # Sanitize agent and model names for use in namespace (lowercase, replace special chars with hyphens)
    local agent_slug=$(echo "$agent_type" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

    local namespace_base
    if [ -n "$model_name" ]; then
        local model_slug=$(echo "$model_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
        namespace_base="${agent_slug}-${model_slug}"
    else
        namespace_base="${agent_slug}"
    fi

    # Add timestamp and random suffix for uniqueness
    # Format: YYYYMMDD-HHMMSS-XXXXXXXX (15 + 1 + 8 = 24 chars)
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local random_suffix=$(head -c 4 /dev/urandom | xxd -p)
    local suffix="${timestamp}-${random_suffix}"

    # Kubernetes namespace limit is 63 characters
    # We need space for: base + "-" + suffix (24 chars)
    # So base can be at most: 63 - 1 - 24 = 38 chars
    local max_base_length=38
    if [ ${#namespace_base} -gt $max_base_length ]; then
        namespace_base="${namespace_base:0:$max_base_length}"
        # Remove trailing hyphen if we cut in the middle
        namespace_base="${namespace_base%-}"
    fi

    echo "${namespace_base}-${suffix}"
}

# Run evaluations for all agent+model combinations
if [ "$PARALLEL" = true ]; then
    echo "Running evaluations in parallel..." | tee -a "$RUN_LOG"

    # Determine max parallel jobs
    if [ "$MAX_PARALLEL_JOBS" -eq 0 ]; then
        MAX_PARALLEL_JOBS=$TOTAL_COMBINATIONS
    fi

    # Arrays to track background jobs
    declare -a PIDS
    declare -a NAMESPACES
    declare -a JOB_AGENTS
    declare -a JOB_MODELS
    declare -a JOB_START_TIMES

    # Launch evaluations
    for i in "${!AGENTS[@]}"; do
        # Wait if we've hit the max parallel jobs
        set +u
        num_pids=${#PIDS[@]}
        set -u
        while [ "$num_pids" -ge "$MAX_PARALLEL_JOBS" ]; do
            # Check if any job has completed
            for j in "${!PIDS[@]}"; do
                if ! kill -0 "${PIDS[$j]}" 2>/dev/null; then
                    # Job completed, wait for it
                    wait "${PIDS[$j]}"

                    # Remove from arrays
                    unset PIDS[$j]
                    unset NAMESPACES[$j]
                    unset JOB_AGENTS[$j]
                    unset JOB_MODELS[$j]
                    unset JOB_START_TIMES[$j]

                    # Reindex arrays
                    PIDS=("${PIDS[@]}")
                    NAMESPACES=("${NAMESPACES[@]}")
                    JOB_AGENTS=("${JOB_AGENTS[@]}")
                    JOB_MODELS=("${JOB_MODELS[@]}")
                    JOB_START_TIMES=("${JOB_START_TIMES[@]}")

                    # Update count
                    set +u
                    num_pids=${#PIDS[@]}
                    set -u
                    break
                fi
            done
            sleep 0.1
        done

        # Generate unique namespace for this eval
        unique_ns=$(generate_unique_namespace "${AGENTS[$i]}" "${MODELS[$i]}")

        # Build prefix for this combination
        if [ -n "${MODELS[$i]}" ]; then
            combo_prefix="[${AGENTS[$i]}/${MODELS[$i]}]"
        else
            combo_prefix="[${AGENTS[$i]}]"
        fi

        timestamp=$(date '+%H:%M:%S')
        echo "[$timestamp] $combo_prefix Starting with namespace $unique_ns..." | tee -a "$RUN_LOG"

        # Run in background
        job_start_time=$(date +%s)
        run_eval "${AGENTS[$i]}" "${MODELS[$i]}" "$unique_ns" &
        pid=$!

        # Store job info
        PIDS+=($pid)
        NAMESPACES+=("$unique_ns")
        JOB_AGENTS+=("${AGENTS[$i]}")
        JOB_MODELS+=("${MODELS[$i]}")
        JOB_START_TIMES+=($job_start_time)
    done

    # Wait for all remaining jobs to complete
    set +u
    remaining_pids=${#PIDS[@]}
    set -u
    if [ "$remaining_pids" -gt 0 ]; then
        echo "Waiting for $remaining_pids remaining job(s) to complete..." | tee -a "$RUN_LOG"
        # Wait for all background jobs
        wait
    else
        echo "All jobs completed" | tee -a "$RUN_LOG"
    fi
else
    # Sequential execution
    for i in "${!AGENTS[@]}"; do
        # Generate unique namespace even for sequential execution
        unique_ns=$(generate_unique_namespace "${AGENTS[$i]}" "${MODELS[$i]}")
        echo "Using namespace: $unique_ns" | tee -a "$RUN_LOG"

        run_eval "${AGENTS[$i]}" "${MODELS[$i]}" "$unique_ns" || true
        echo "" | tee -a "$RUN_LOG"
    done
fi

# Calculate final results by checking all JSON output files from this run
echo "" | tee -a "$RUN_LOG"
echo "Calculating final results from test outputs..." | tee -a "$RUN_LOG"

# Reset counters (they may be incorrect due to parallel execution in subshells)
ACTUAL_SUCCESS_COUNT=0
ACTUAL_FAILURE_COUNT=0

# Arrays to track which combinations succeeded/failed
declare -a SUCCESSFUL_COMBINATIONS
declare -a FAILED_COMBINATIONS

# Find all JSON files generated during this run in the results directory
results_dir="$SCRIPT_DIR/results"
if [ -d "$results_dir" ]; then
    # Process each JSON file created during this run
    for json_file in "$results_dir"/gevals-*-out.json; do
        if [ -f "$json_file" ]; then
            # Check if file was created during this run (modified after RUN_START_TIME)
            file_mtime=$(stat -c %Y "$json_file" 2>/dev/null || stat -f %m "$json_file" 2>/dev/null || echo 0)
            if [ "$file_mtime" -ge "$RUN_START_TIME" ]; then
                # Extract combination name from filename (remove gevals- prefix, -TIMESTAMP-out.json suffix)
                combination=$(basename "$json_file" | sed 's/^gevals-//' | sed 's/-[0-9]\{8\}-[0-9]\{6\}-out\.json$//')

                # Check if any tasks failed or had errors
                if grep -q '"status"[[:space:]]*:[[:space:]]*"\(error\|fail\)"' "$json_file"; then
                    ((ACTUAL_FAILURE_COUNT++))
                    FAILED_COMBINATIONS+=("$combination")
                else
                    ((ACTUAL_SUCCESS_COUNT++))
                    SUCCESSFUL_COMBINATIONS+=("$combination")
                fi
            fi
        fi
    done
fi

# Use the actual counts from JSON files
SUCCESS_COUNT=$ACTUAL_SUCCESS_COUNT
FAILURE_COUNT=$ACTUAL_FAILURE_COUNT
# SKIPPED_COUNT is still accurate from the main process
# (only incremented when we skip before running gevals)

# Create results summary JSON file
RESULTS_JSON="$results_dir/results-$(date +%Y%m%d-%H%M%S).json"
cat > "$RESULTS_JSON" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "total_combinations": $TOTAL_COMBINATIONS,
  "successful": $SUCCESS_COUNT,
  "failed": $FAILURE_COUNT,
  "skipped": $SKIPPED_COUNT,
  "successful_combinations": [
$(for combo in "${SUCCESSFUL_COMBINATIONS[@]}"; do echo "    \"$combo\","; done | sed '$ s/,$//')
  ],
  "failed_combinations": [
$(for combo in "${FAILED_COMBINATIONS[@]}"; do echo "    \"$combo\","; done | sed '$ s/,$//')
  ]
}
EOF

echo "Results summary saved to: $RESULTS_JSON" | tee -a "$RUN_LOG"
echo "" | tee -a "$RUN_LOG"

# Print summary
echo "========================================" | tee -a "$RUN_LOG"
echo "Evaluation run complete" | tee -a "$RUN_LOG"
echo "Date: $(date)" | tee -a "$RUN_LOG"
echo "Total combinations: $TOTAL_COMBINATIONS" | tee -a "$RUN_LOG"
echo "Successful: $SUCCESS_COUNT" | tee -a "$RUN_LOG"
echo "Failed: $FAILURE_COUNT" | tee -a "$RUN_LOG"
echo "Skipped: $SKIPPED_COUNT" | tee -a "$RUN_LOG"

# Show which combinations failed
if [ $FAILURE_COUNT -gt 0 ]; then
    echo "" | tee -a "$RUN_LOG"
    echo "Failed combinations:" | tee -a "$RUN_LOG"
    for combo in "${FAILED_COMBINATIONS[@]}"; do
        echo "  - $combo" | tee -a "$RUN_LOG"
    done
fi

echo "========================================" | tee -a "$RUN_LOG"

# Exit with error if any evaluations failed
if [ $FAILURE_COUNT -gt 0 ]; then
    exit 1
fi
