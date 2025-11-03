#!/usr/bin/env bash
# Configuration file for model credentials and settings
# This file sources API keys and base URLs from gnome-keyring using secret-tool
# Each model has its own individual base URL and API key stored separately
#
# This script is designed to work with ANY model name - no predefined list required.
# Just provide the model name when running the script, and it will look up the
# corresponding secrets from gnome-keyring.

# Function to retrieve secrets from gnome-keyring
get_secret() {
    local service="$1"
    local account="$2"
    secret-tool lookup service "$service" account "$account" 2>/dev/null
}

# Function to normalize model name to a safe service name
# Converts model name to lowercase and replaces special chars with hyphens
normalize_model_name() {
    local model_name="$1"
    echo "$model_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9.-]/-/g'
}

# Function to get model configuration from secrets
# Each model stores its own base-url and api-key in gnome-keyring
get_model_config() {
    local model_name="$1"
    local service_name=$(normalize_model_name "$model_name")

    # Get model-specific secrets
    local api_key=$(get_secret "model-$service_name" "api-key")
    local base_url=$(get_secret "model-$service_name" "base-url")
    local model_id=$(get_secret "model-$service_name" "model-id")

    # Validate that we have required values
    if [ -z "$api_key" ]; then
        echo "Error: API key not found for model $model_name (service: model-$service_name)" >&2
        echo "Error: Store it with: secret-tool store --label='$model_name API Key' service model-$service_name account api-key" >&2
        return 1
    fi

    if [ -z "$base_url" ]; then
        echo "Error: Base URL not found for model $model_name (service: model-$service_name)" >&2
        echo "Error: Store it with: secret-tool store --label='$model_name Base URL' service model-$service_name account base-url" >&2
        return 1
    fi

    # Use stored model-id if available, otherwise use the original model name
    if [ -z "$model_id" ]; then
        model_id="$model_name"
    fi

    echo "MODEL_BASE_URL=$base_url"
    echo "MODEL_KEY=$api_key"
    echo "MODEL_NAME=$model_id"
}

# Function to check if a base URL is OpenAI-compatible
# Tests both /models and /chat/completions endpoints with the provided API key
check_openai_compatibility() {
    local base_url="$1"
    local api_key="$2"
    local model_name="$3"

    # Remove trailing slash from base_url if present
    base_url="${base_url%/}"

    local has_error=false

    # Check /models endpoint
    local models_url="${base_url}/models"
    echo "  Testing GET ${models_url}" >&2
    local models_code
    models_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X GET "${models_url}" \
        -H "Authorization: Bearer ${api_key}" \
        -H "Content-Type: application/json" \
        --max-time 10 \
        2>/dev/null)

    if [ "$models_code" = "200" ]; then
        echo "    ✓ Endpoint accessible (HTTP 200)" >&2
    elif [ "$models_code" = "401" ]; then
        echo "    ✗ Authentication failed (HTTP 401)" >&2
        has_error=true
    elif [ "$models_code" = "404" ]; then
        echo "    ⚠ Endpoint not found (HTTP 404)" >&2
    elif [ -z "$models_code" ]; then
        echo "    ✗ Could not connect to endpoint" >&2
        has_error=true
    else
        echo "    ⚠ Returned HTTP $models_code" >&2
    fi

    # Check /chat/completions endpoint with a minimal test request
    local chat_url="${base_url}/chat/completions"
    echo "  Testing POST ${chat_url}" >&2
    local chat_code
    local chat_response
    chat_response=$(mktemp)
    chat_code=$(curl -s -w "%{http_code}" -o "$chat_response" \
        -X POST "${chat_url}" \
        -H "Authorization: Bearer ${api_key}" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$model_name\",\"messages\":[{\"role\":\"user\",\"content\":\"test\"}],\"max_tokens\":1}" \
        --max-time 10 \
        2>/dev/null)

    if [ "$chat_code" = "200" ]; then
        echo "    ✓ Endpoint accessible (HTTP 200)" >&2
    elif [ "$chat_code" = "401" ]; then
        echo "    ✗ Authentication failed (HTTP 401)" >&2
        has_error=true
    elif [ "$chat_code" = "404" ]; then
        echo "    ✗ Endpoint not found (HTTP 404)" >&2
        has_error=true
    elif [ "$chat_code" = "400" ]; then
        # 400 might be acceptable - could be invalid model name or request format
        echo "    ⚠ Returned HTTP 400 (check model name)" >&2
        # Check if response contains model-not-found type error
        if grep -qi "model.*not.*found\|invalid.*model" "$chat_response" 2>/dev/null; then
            echo "    ⚠ Model '$model_name' may not exist at this endpoint" >&2
        fi
    elif [ -z "$chat_code" ]; then
        echo "    ✗ Could not connect to endpoint" >&2
        has_error=true
    else
        echo "    ⚠ Returned HTTP $chat_code" >&2
    fi

    rm -f "$chat_response"

    # Check /completions endpoint (legacy text completion)
    local completions_url="${base_url}/completions"
    echo "  Testing POST ${completions_url}" >&2
    local completions_code
    local completions_response
    completions_response=$(mktemp)
    completions_code=$(curl -s -w "%{http_code}" -o "$completions_response" \
        -X POST "${completions_url}" \
        -H "Authorization: Bearer ${api_key}" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$model_name\",\"prompt\":\"test\",\"max_tokens\":1}" \
        --max-time 10 \
        2>/dev/null)

    if [ "$completions_code" = "200" ]; then
        echo "    ✓ Endpoint accessible (HTTP 200)" >&2
    elif [ "$completions_code" = "401" ]; then
        echo "    ✗ Authentication failed (HTTP 401)" >&2
        has_error=true
    elif [ "$completions_code" = "404" ]; then
        echo "    ⚠ Endpoint not found (HTTP 404) - not all providers support legacy completions" >&2
    elif [ "$completions_code" = "400" ]; then
        echo "    ⚠ Returned HTTP 400 - may not support this endpoint or model" >&2
    elif [ -z "$completions_code" ]; then
        echo "    ✗ Could not connect to endpoint" >&2
        has_error=true
    else
        echo "    ⚠ Returned HTTP $completions_code" >&2
    fi

    rm -f "$completions_response"

    # Check /embeddings endpoint
    local embeddings_url="${base_url}/embeddings"
    echo "  Testing POST ${embeddings_url}" >&2
    local embeddings_code
    local embeddings_response
    embeddings_response=$(mktemp)
    embeddings_code=$(curl -s -w "%{http_code}" -o "$embeddings_response" \
        -X POST "${embeddings_url}" \
        -H "Authorization: Bearer ${api_key}" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$model_name\",\"input\":\"test\"}" \
        --max-time 10 \
        2>/dev/null)

    if [ "$embeddings_code" = "200" ]; then
        echo "    ✓ Endpoint accessible (HTTP 200)" >&2
    elif [ "$embeddings_code" = "401" ]; then
        echo "    ✗ Authentication failed (HTTP 401)" >&2
        has_error=true
    elif [ "$embeddings_code" = "404" ]; then
        echo "    ⚠ Endpoint not found (HTTP 404) - may not support embeddings" >&2
    elif [ "$embeddings_code" = "400" ]; then
        echo "    ⚠ Returned HTTP 400 - may not be an embeddings model" >&2
    elif [ -z "$embeddings_code" ]; then
        echo "    ✗ Could not connect to endpoint" >&2
        has_error=true
    else
        echo "    ⚠ Returned HTTP $embeddings_code" >&2
    fi

    rm -f "$embeddings_response"

    # Check /moderations endpoint
    local moderations_url="${base_url}/moderations"
    echo "  Testing POST ${moderations_url}" >&2
    local moderations_code
    moderations_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${moderations_url}" \
        -H "Authorization: Bearer ${api_key}" \
        -H "Content-Type: application/json" \
        -d "{\"input\":\"test\"}" \
        --max-time 10 \
        2>/dev/null)

    if [ "$moderations_code" = "200" ]; then
        echo "    ✓ Endpoint accessible (HTTP 200)" >&2
    elif [ "$moderations_code" = "401" ]; then
        echo "    ✗ Authentication failed (HTTP 401)" >&2
        has_error=true
    elif [ "$moderations_code" = "404" ]; then
        echo "    ⚠ Endpoint not found (HTTP 404) - may not support moderations" >&2
    elif [ -z "$moderations_code" ]; then
        echo "    ✗ Could not connect to endpoint" >&2
        has_error=true
    else
        echo "    ⚠ Returned HTTP $moderations_code" >&2
    fi

    if [ "$has_error" = true ]; then
        return 1
    else
        echo "  ✓ API endpoint validation complete" >&2
        return 0
    fi
}

# Function to validate secrets for specific models
# Usage: validate_model_secrets [--check-api] "model1" "model2" ...
validate_model_secrets() {
    local check_api=false
    local models=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check-api)
                check_api=true
                shift
                ;;
            *)
                models+=("$1")
                shift
                ;;
        esac
    done

    local errors=0

    if [ ${#models[@]} -eq 0 ]; then
        echo "No models specified for validation" >&2
        return 0
    fi

    echo "Validating secrets for ${#models[@]} model(s)..." >&2
    if [ "$check_api" = true ]; then
        echo "API endpoint connectivity check: ENABLED" >&2
    fi
    echo "" >&2

    for model_name in "${models[@]}"; do
        local service_name=$(normalize_model_name "$model_name")
        local api_key=$(get_secret "model-$service_name" "api-key")
        local base_url=$(get_secret "model-$service_name" "base-url")
        local model_id=$(get_secret "model-$service_name" "model-id")

        if [ -z "$api_key" ] && [ -z "$base_url" ]; then
            echo "ERROR: Model '$model_name' is missing both API key and base URL" >&2
            echo "  Service name: model-$service_name" >&2
            ((errors++))
        elif [ -z "$api_key" ]; then
            echo "ERROR: Model '$model_name' is missing API key" >&2
            echo "  Service name: model-$service_name" >&2
            ((errors++))
        elif [ -z "$base_url" ]; then
            echo "ERROR: Model '$model_name' is missing base URL" >&2
            echo "  Service name: model-$service_name" >&2
            ((errors++))
        else
            echo "OK: Model '$model_name' has API key and base URL configured" >&2
            if [ -z "$model_id" ]; then
                echo "  Note: No custom model-id set, will use '$model_name'" >&2
            else
                echo "  Custom model-id: $model_id" >&2
            fi

            # Check API endpoint if requested
            if [ "$check_api" = true ]; then
                if ! check_openai_compatibility "$base_url" "$api_key" "$model_name"; then
                    ((errors++))
                fi
            fi
        fi
        echo "" >&2
    done

    if [ $errors -gt 0 ]; then
        echo "Found $errors error(s). Please configure missing secrets." >&2
        return 1
    else
        echo "All specified models are properly configured!" >&2
        return 0
    fi
}

# Export the functions for use in other scripts
export -f get_model_config
export -f validate_model_secrets
export -f check_openai_compatibility
export -f normalize_model_name
