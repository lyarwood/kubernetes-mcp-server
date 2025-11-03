# Agent and Model Evaluation System

This directory contains scripts to run gevals against **any** combination of agent types and OpenAI-compatible models by looking up model credentials from gnome-keyring.

## Files

- **`run-agent-model-evals.sh`** - Main script to run evaluations against agent+model combinations
- **`model-configs.sh`** - Configuration file that retrieves per-model API keys and base URLs from gnome-keyring
- **`EVAL_README.md`** - This file

## Agent Types

The system supports multiple agent types, each in its own subdirectory:

- **`openai-agent/`** - OpenAI-compatible agent implementation
- **`gemini/`** - Google Gemini CLI agent implementation
- **`claude-code/`** - Claude Code agent implementation

Each agent directory contains:
- `eval.yaml` - Evaluation configuration specific to the agent
- `agent.yaml` - Agent configuration and system prompts
- Optional wrapper scripts for agent-specific setup

## Architecture

This system is designed to work with:
1. **Multiple agent types** - Test different agent implementations
2. **Any model name** - No predefined model list required
3. **Individual model credentials** - Each model stores its own API key and base URL
4. **Explicit agent/model pairing** - Specify exactly which combinations to test
5. **Optional model specification** - Some agents have pre-configured models and don't require explicit model names
6. **Unique namespaces** - Each test run uses a unique Kubernetes namespace to avoid conflicts
7. **Parallel execution** - Run multiple evaluations concurrently with automatic namespace isolation

Agent model requirements:
- **`openai-agent`** - Requires explicit model specification via `-a openai-agent/model-name`
- **`gemini`** - Uses pre-configured model, specify as `-a gemini` (no model needed)
- **`claude-code`** - Uses pre-configured model, specify as `-a claude-code` (no model needed)

For agents requiring models:
1. Choose a model name (e.g., `gemini-2.0-flash`, `claude-sonnet-4@20250514`, `mistralai/Mistral-7B-Instruct-v0.3`)
2. Store the model's credentials in gnome-keyring using the normalized service name
3. Run the script with `-a "agent-type/model-name"`

For agents with pre-configured models:
1. Run the script with `-a "agent-type"` (e.g., `-a gemini` or `-a claude-code`)

Every model has its own individual secrets:
- **API Key** - Stored in gnome-keyring as `service: model-{normalized-name} account: api-key`
- **Base URL** - Stored in gnome-keyring as `service: model-{normalized-name} account: base-url`
- **Model ID** (optional) - Stored in gnome-keyring as `service: model-{normalized-name} account: model-id`

This allows maximum flexibility - you can use any model from any provider, route models through different proxies, or point to entirely different endpoints.

## Setup

### 1. Install secret-tool

The scripts use `secret-tool` from `libsecret` to retrieve secrets from gnome-keyring:

```bash
# Fedora/RHEL
sudo dnf install libsecret

# Ubuntu/Debian
sudo apt-get install libsecret-tools
```

### 2. Store Model Secrets in gnome-keyring

Each model requires two secrets to be stored: `api-key` and `base-url`. The service name is derived from the model name by normalizing it (lowercase, special characters replaced with hyphens, prefixed with `model-`).

**Important:** You only need to configure the models you actually plan to use. There's no need to configure all the examples below - these are just for reference.

#### Example: mistralai/Mistral-7B-Instruct-v0.3
Service name: `model-mistralai-mistral-7b-instruct-v0.3`

```bash
# API Key
secret-tool store --label='Mistral 7B API Key' \
  service model-mistralai-mistral-7b-instruct-v0.3 \
  account api-key

# Base URL (enter the OpenAI-compatible endpoint URL)
secret-tool store --label='Mistral 7B Base URL' \
  service model-mistralai-mistral-7b-instruct-v0.3 \
  account base-url
# Example URL: https://api.fireworks.ai/inference/v1

# Optional: Model ID (if the API expects a different model identifier)
secret-tool store --label='Mistral 7B Model ID' \
  service model-mistralai-mistral-7b-instruct-v0.3 \
  account model-id
# Example: accounts/fireworks/models/mistralai/Mistral-7B-Instruct-v0.3
```

#### Model: gemini-2.0-flash
Service name: `model-gemini-2.0-flash`

```bash
secret-tool store --label='Gemini 2.0 Flash API Key' \
  service model-gemini-2.0-flash \
  account api-key

secret-tool store --label='Gemini 2.0 Flash Base URL' \
  service model-gemini-2.0-flash \
  account base-url
# Example URL: https://generativelanguage.googleapis.com/v1beta/openai/
```

#### Model: claude-sonnet-4@20250514
Service name: `model-claude-sonnet-4-20250514`

```bash
secret-tool store --label='Claude Sonnet 4 API Key' \
  service model-claude-sonnet-4-20250514 \
  account api-key

secret-tool store --label='Claude Sonnet 4 Base URL' \
  service model-claude-sonnet-4-20250514 \
  account base-url
# Example URL: https://api.anthropic.com/v1
```

### 3. Verify Model Secrets

You can verify that your model secrets are stored correctly:

```bash
# Check a specific model
secret-tool lookup service model-gemini-2.0-flash account api-key
secret-tool lookup service model-gemini-2.0-flash account base-url

# List all secrets for a model
secret-tool search service model-gemini-2.0-flash

# Or use the validation command to check all models at once
./run-agent-model-evals.sh -m "gemini-2.0-flash" --validate-secrets
```

The `--validate-secrets` command will show you the status of all models and tell you exactly which secrets are missing.

## Usage

### Run Evaluations

The script requires you to specify at least one agent or agent/model combination using the `-a` flag.

**Format:**
- For agents requiring models (openai-agent): `-a agent-type/model-name`
- For agents with pre-configured models (gemini, claude-code): `-a agent-type`

```bash
# Run evaluation with agent that requires a model (openai-agent)
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash

# Run evaluation with agents that have pre-configured models
./run-agent-model-evals.sh -a gemini
./run-agent-model-evals.sh -a claude-code

# Run evaluations for multiple combinations
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash -a openai-agent/claude-sonnet-4@20250514

# Test one model with openai-agent and pre-configured agents
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash -a gemini -a claude-code

# Mix and match any combinations
./run-agent-model-evals.sh \
  -a openai-agent/gemini-2.0-flash \
  -a openai-agent/claude-sonnet-4@20250514 \
  -a gemini \
  -a claude-code

# Run with custom model name for openai-agent
./run-agent-model-evals.sh -a openai-agent/your-custom-model-name
```

### Validate Secrets

To check if models used in specific combinations are properly configured without running evaluations:

```bash
# Validate models used in one combination
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash --validate-secrets

# Validate models used in multiple combinations (including agent-only)
./run-agent-model-evals.sh \
  -a openai-agent/gemini-2.0-flash \
  -a openai-agent/claude-sonnet-4@20250514 \
  -a gemini \
  --validate-secrets

# Validate agent-only combinations (no models to validate)
./run-agent-model-evals.sh -a gemini -a claude-code --validate-secrets
```

This will extract the unique models from your combinations and show you which ones have both API keys and base URLs configured. For agent-only combinations (gemini, claude-code), no model validation is performed.

### Check API Endpoints

To validate that the base URLs are OpenAI-compatible and accessible, add the `--check-api` flag:

```bash
# Validate secrets AND check API endpoint connectivity
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash --validate-secrets --check-api

# Check multiple combinations (validates unique models)
./run-agent-model-evals.sh \
  -a openai-agent/gemini-2.0-flash \
  -a gemini/claude-sonnet-4@20250514 \
  --validate-secrets --check-api
```

This performs HTTP requests to test common OpenAI-compatible API endpoints:
1. **`GET /models`** - Lists available models (informational)
2. **`POST /chat/completions`** - Creates a test chat completion (critical for agent execution)
3. **`POST /completions`** - Tests legacy text completion endpoint (informational)
4. **`POST /embeddings`** - Tests embeddings endpoint (informational)
5. **`POST /moderations`** - Tests content moderation endpoint (informational)

The validation checks:
- ✓ The endpoints are accessible
- ✓ The API key is valid
- ✓ The chat completions endpoint works (critical - used by agents)
- ⚠ Non-critical endpoints may return 404 if not supported by the provider

**Example successful validation:**
```bash
$ ./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash --validate-secrets --check-api

OK: Model 'gemini-2.0-flash' has API key and base URL configured
  Note: No custom model-id set, will use 'gemini-2.0-flash'
  Testing GET https://generativelanguage.googleapis.com/v1beta/openai/models
    ✓ Endpoint accessible (HTTP 200)
  Testing POST https://generativelanguage.googleapis.com/v1beta/openai/chat/completions
    ✓ Endpoint accessible (HTTP 200)
  Testing POST https://generativelanguage.googleapis.com/v1beta/openai/completions
    ⚠ Endpoint not found (HTTP 404) - not all providers support legacy completions
  Testing POST https://generativelanguage.googleapis.com/v1beta/openai/embeddings
    ⚠ Returned HTTP 400 - may not be an embeddings model
  Testing POST https://generativelanguage.googleapis.com/v1beta/openai/moderations
    ⚠ Endpoint not found (HTTP 404) - may not support moderations
  ✓ API endpoint validation complete

All specified models are properly configured!
```

**Note:** The `--check-api` flag only works with `--validate-secrets` and requires network connectivity to the API endpoints. Warnings (⚠) are informational and don't cause validation to fail - only authentication errors (✗) cause failure.

### Dry Run

To see what commands would be executed without actually running them:

```bash
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash --dry-run
```

### Verbose Output

To see detailed configuration and environment variables:

```bash
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash -v
```

### Custom Output Directory

To specify a custom output directory for log files:

```bash
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash -o /path/to/results
```

### Custom Output Prefix

To add a prefix to the output files (useful for organizing experiments or runs):

```bash
# Without prefix (default)
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash
# Creates:
#   gevals-openai-agent-gemini-2.0-flash-20250106-143022-out.json
#   gevals-openai-agent-gemini-2.0-flash-20250106-143022-out.log

# With prefix
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash -p "experiment-1"
# Creates:
#   gevals-experiment-1-openai-agent-gemini-2.0-flash-20250106-143022-out.json
#   gevals-experiment-1-openai-agent-gemini-2.0-flash-20250106-143022-out.log

# Multiple combinations with the same prefix
./run-agent-model-evals.sh \
  -a openai-agent/gemini-2.0-flash \
  -a gemini/gemini-2.0-flash \
  -p "baseline-test"
# Creates (timestamps will vary):
#   gevals-baseline-test-openai-agent-gemini-2.0-flash-20250106-143022-out.json
#   gevals-baseline-test-openai-agent-gemini-2.0-flash-20250106-143022-out.log
#   gevals-baseline-test-gemini-gemini-2.0-flash-20250106-143045-out.json
#   gevals-baseline-test-gemini-gemini-2.0-flash-20250106-143045-out.log
```

### Parallel Execution

To run multiple evaluations in parallel for faster completion:

```bash
# Run all combinations in parallel (each gets a unique namespace)
./run-agent-model-evals.sh \
  -a openai-agent/gemini-2.0-flash \
  -a openai-agent/claude-sonnet-4@20250514 \
  -a gemini \
  -a claude-code \
  --parallel

# Limit parallel jobs to 2 at a time
./run-agent-model-evals.sh \
  -a openai-agent/gemini-2.0-flash \
  -a openai-agent/claude-sonnet-4@20250514 \
  -a gemini \
  --parallel -j 2
```

**How it works:**
- Each evaluation runs in its own unique Kubernetes namespace (e.g., `vm-test-20251106-162422-a3b4c5d6`)
- Namespaces are automatically created and cleaned up
- The `--parallel` flag enables concurrent execution
- The `-j N` flag limits the maximum number of parallel jobs (default: unlimited)
- Progress is logged in real-time to the run log file

**Benefits:**
- Much faster evaluation of multiple combinations
- No namespace conflicts between parallel runs
- Automatic resource isolation

**Note:** Make sure your Kubernetes cluster has sufficient resources to handle multiple concurrent VMs.

### Help

For full usage information:

```bash
./run-agent-model-evals.sh --help
```

## Example Model Configurations

Here are some example normalized service names for common models:

| Model Name Example | Normalized Service Name |
|-------------------|-------------------------|
| `mistralai/Mistral-7B-Instruct-v0.3` | `model-mistralai-mistral-7b-instruct-v0.3` |
| `ibm-granite/granite-4.0-h-tiny` | `model-ibm-granite-granite-4.0-h-tiny` |
| `ibm-granite/granite-4.0-h-micro` | `model-ibm-granite-granite-4.0-h-micro` |
| `Qwen/Qwen3-14B` | `model-qwen-qwen3-14b` |
| `gemini-2.0-flash` | `model-gemini-2.0-flash` |
| `gemini-2.5-pro` | `model-gemini-2.5-pro` |
| `claude-sonnet-4@20250514` | `model-claude-sonnet-4-20250514` |
| `claude-3-5-haiku@20241022` | `model-claude-3-5-haiku-20241022` |

## Using Any Model

To use a model that's not in the examples above:

1. Determine the normalized service name (lowercase, special chars replaced with hyphens):
   - `new-provider/new-model-v1` → `model-new-provider-new-model-v1`
   - `MyModel@2024` → `model-mymodel-2024`

2. Store the secrets:

```bash
secret-tool store --label='New Model API Key' \
  service model-new-provider-new-model-v1 \
  account api-key

secret-tool store --label='New Model Base URL' \
  service model-new-provider-new-model-v1 \
  account base-url
```

3. Optionally store a custom model ID if the API expects a different identifier:

```bash
secret-tool store --label='New Model ID' \
  service model-new-provider-new-model-v1 \
  account model-id
```

4. Run the evaluation:

```bash
./run-agent-model-evals.sh -a openai-agent -m "new-provider/new-model-v1"
```

That's it! No need to edit any configuration files - just store the secrets and run.

## Output

The script generates several types of output files:

### Log Files (in specified output directory)

The script creates a `results/` directory (or custom directory specified with `-o`) containing:

- Individual log files for each agent+model evaluation (`gevals-{agent-slug}-{model-slug}-{timestamp}.log`)
- A run summary log file (`gevals-run-{timestamp}.log`)

### Gevals Output Files (in project results directory)

After each successful evaluation, the script automatically:
1. Generates a formatted view file from the JSON output using `gevals view`
2. Renames both files to include the optional prefix, agent type, model name, and timestamp
3. Moves them to `pkg/toolsets/kubevirt/tests/results/`

File naming pattern:
- Without prefix: `gevals-{agent-slug}-{model-slug}-{timestamp}-out.{json|log}`
- With prefix: `gevals-{prefix}-{agent-slug}-{model-slug}-{timestamp}-out.{json|log}`

Where:
- `{prefix}` is the optional prefix specified with `-p` or `--prefix`
- `{agent-slug}` is the normalized agent type name
- `{model-slug}` is the normalized model name
- `{timestamp}` is the date and time in format `YYYYMMDD-HHMMSS` (e.g., `20250106-143022`)

Files created:
- `.json` - Raw evaluation results in JSON format (generated by gevals run)
- `.log` - Formatted view output (generated by gevals view)

Examples:

**Without prefix:**
```bash
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash
```
Creates (timestamp will vary):
- `pkg/toolsets/kubevirt/tests/results/gevals-openai-agent-gemini-2.0-flash-20250106-143022-out.json`
- `pkg/toolsets/kubevirt/tests/results/gevals-openai-agent-gemini-2.0-flash-20250106-143022-out.log`

**With prefix:**
```bash
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash -p "baseline"
```
Creates (timestamp will vary):
- `pkg/toolsets/kubevirt/tests/results/gevals-baseline-openai-agent-gemini-2.0-flash-20250106-143022-out.json`
- `pkg/toolsets/kubevirt/tests/results/gevals-baseline-openai-agent-gemini-2.0-flash-20250106-143022-out.log`

**Multiple combinations:**
```bash
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash -a gemini/gemini-2.0-flash
```
Creates (timestamps will vary):
- `pkg/toolsets/kubevirt/tests/results/gevals-openai-agent-gemini-2.0-flash-20250106-143022-out.json`
- `pkg/toolsets/kubevirt/tests/results/gevals-openai-agent-gemini-2.0-flash-20250106-143022-out.log`
- `pkg/toolsets/kubevirt/tests/results/gevals-gemini-gemini-2.0-flash-20250106-143045-out.json`
- `pkg/toolsets/kubevirt/tests/results/gevals-gemini-gemini-2.0-flash-20250106-143045-out.log`

## Understanding Service Names

Service names are automatically normalized from model names:
- Convert to lowercase
- Replace non-alphanumeric characters (except dots and hyphens) with hyphens
- Prefix with `model-`

Examples:
- `gemini-2.0-flash` → `model-gemini-2.0-flash`
- `claude-sonnet-4@20250514` → `model-claude-sonnet-4-20250514`
- `mistralai/Mistral-7B-Instruct-v0.3` → `model-mistralai-mistral-7b-instruct-v0.3`

You can use the `normalize_model_name` function to check the service name:

```bash
source model-configs.sh
normalize_model_name "Your/Model@Name"
```

## Troubleshooting

### Model Secrets Not Found

If you get errors about missing secrets:

```
ERROR: Model 'gemini-2.0-flash' is missing both API key and base URL
  Service name: model-gemini-2.0-flash
```

Make sure you've stored both the `api-key` and `base-url` for that model using the exact service name shown.

### Wrong Service Name

If you're unsure about the service name, use the validation command:

```bash
./run-agent-model-evals.sh -m "your-model-name" --validate-secrets
```

This will show you the exact service names for the specified models.

### API Endpoint Not Accessible

If the `--check-api` validation fails, you'll see specific error messages:

**HTTP 401 - Authentication Failed:**
```
✗ API authentication failed (HTTP 401) - check API key
```
→ Verify your API key is correct and hasn't expired.

**HTTP 404 - Endpoint Not Found:**
```
✗ /chat/completions endpoint not found (HTTP 404)
```
→ Check that your base URL is correct and includes the proper path (e.g., `/v1` for OpenAI).
→ The `/models` endpoint might work while `/chat/completions` doesn't - always use `--check-api` to validate both.

**Connection Failed:**
```
✗ Could not connect to API endpoint - check base URL and network
```
→ Verify the base URL is correct and you have network connectivity.

**Debugging workflow:**
```bash
# 1. Check secrets are stored
./run-agent-model-evals.sh -m "gemini-2.0-flash" --validate-secrets

# 2. Test API connectivity (including chat/completions)
./run-agent-model-evals.sh -m "gemini-2.0-flash" --validate-secrets --check-api

# 3. Manually test chat completions endpoint
BASE_URL=$(secret-tool lookup service model-gemini-2.0-flash account base-url)
API_KEY=$(secret-tool lookup service model-gemini-2.0-flash account api-key)
curl -X POST "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gemini-2.0-flash","messages":[{"role":"user","content":"test"}],"max_tokens":1}'
```

### Unknown Agent Type

If you get an error about an unknown agent type:

```
Error: Unknown agent type 'my-agent'
Available agents: openai-agent gemini claude-code
```

Make sure you're using one of the available agent types listed in the error message.

### Checking Stored Secrets

To see all secrets for a model:

```bash
secret-tool search service model-gemini-2.0-flash
```

To retrieve a specific secret value:

```bash
secret-tool lookup service model-gemini-2.0-flash account api-key
secret-tool lookup service model-gemini-2.0-flash account base-url
secret-tool lookup service model-gemini-2.0-flash account model-id
```

### Removing Stored Secrets

To remove a stored secret from gnome-keyring:

```bash
# Remove an API key
secret-tool clear service model-gemini-2.0-flash account api-key

# Remove a base URL
secret-tool clear service model-gemini-2.0-flash account base-url

# Remove a model ID
secret-tool clear service model-gemini-2.0-flash account model-id
```

### gevals Command Not Found

Make sure the `gevals` binary is in your PATH or adjust the script to use the full path to the binary.

### Model ID vs Model Name

Some API providers expect a specific model identifier that differs from the friendly model name:

- **Model Name**: What you call the model in your script (e.g., `mistralai/Mistral-7B-Instruct-v0.3`)
- **Model ID**: What the API expects (e.g., `accounts/fireworks/models/mistralai/Mistral-7B-Instruct-v0.3`)

If the API requires a different identifier, store it as the `model-id`:

```bash
secret-tool store --label='Model ID' \
  service model-mistralai-mistral-7b-instruct-v0.3 \
  account model-id
# Enter: accounts/fireworks/models/mistralai/Mistral-7B-Instruct-v0.3
```

If no `model-id` is stored, the script will use the original model name.

## Environment Variables

The scripts set these environment variables for each model evaluation:

- `MODEL_BASE_URL` - The OpenAI-compatible API base URL (from secrets)
- `MODEL_KEY` - The API key for authentication (from secrets)
- `MODEL_NAME` - The model name/identifier (from secrets if `model-id` is set, otherwise the original model name)
- `SYSTEM_PROMPT` - Optional system prompt (can be set externally)

These variables are consumed by the agent implementations in each agent directory.

## Example: Complete Setup for One Agent+Model Combination

Here's a complete example for setting up and running the `openai-agent` with `gemini-2.0-flash`:

```bash
# 1. Store the API key
secret-tool store --label='Gemini 2.0 Flash API Key' \
  service model-gemini-2.0-flash \
  account api-key
# When prompted, enter your Google AI API key

# 2. Store the base URL
secret-tool store --label='Gemini 2.0 Flash Base URL' \
  service model-gemini-2.0-flash \
  account base-url
# When prompted, enter: https://generativelanguage.googleapis.com/v1beta/openai/

# 3. Verify it's configured
secret-tool search service model-gemini-2.0-flash

# 4. Test just this combination with dry-run
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash --dry-run

# 5. Run the actual evaluation
./run-agent-model-evals.sh -a openai-agent/gemini-2.0-flash
```

## Example: Testing Multiple Combinations

To systematically test across all available agent types:

```bash
# Test gemini-2.0-flash with openai-agent, plus pre-configured agents
./run-agent-model-evals.sh \
  -a openai-agent/gemini-2.0-flash \
  -a gemini \
  -a claude-code
```

To test multiple different models with openai-agent:

```bash
# This will run 2 evaluations (openai-agent with 2 different models)
./run-agent-model-evals.sh \
  -a openai-agent/gemini-2.0-flash \
  -a openai-agent/claude-sonnet-4@20250514
```

To run all available agents (mix of agent/model and agent-only):

```bash
# This will run 4 total evaluations
./run-agent-model-evals.sh \
  -a openai-agent/gemini-2.0-flash \
  -a openai-agent/claude-sonnet-4@20250514 \
  -a gemini \
  -a claude-code
```

Or mix and match specific combinations as needed:

```bash
# Test specific combinations
./run-agent-model-evals.sh \
  -a openai-agent/gemini-2.0-flash \
  -a openai-agent/mistralai/Mistral-7B-Instruct-v0.3 \
  -a gemini \
  -a claude-code
```
