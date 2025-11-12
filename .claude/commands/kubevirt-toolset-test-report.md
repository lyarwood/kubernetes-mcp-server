Generate a comprehensive KubeVirt integration test results report.

## Arguments

- **prefix** (optional): Filter test results by filename prefix (e.g., `with-pause-tool`, `without-pause-tool`). If not provided, all test results will be analyzed.

## Task

Analyze test result files in `pkg/toolsets/kubevirt/tests/results/` and generate a detailed markdown report documenting agent performance, success rates, and insights.

## Steps

1. **Read JSON test result files** matching the appropriate pattern:
   - **With prefix argument**: `pkg/toolsets/kubevirt/tests/results/gevals-{prefix}-*-out.json`
   - **Without prefix**: `pkg/toolsets/kubevirt/tests/results/gevals-*-out.json`

2. **Parse agent data** from each file:
   - Extract agent name from filename (e.g., "claude-code", "gemini", "openai-agent-gemini-2.0-flash")
   - Extract timestamp from filename
   - Parse test results: tasks, pass/fail status, difficulty, assertions
   - Analyze tool usage from callHistory.ToolCalls

3. **Calculate comprehensive statistics**:
   - Per-agent: total tasks, passed, failed, success rate
   - Per-task: which agents passed/failed, common issues
   - Per-difficulty: success rates across difficulty levels
   - Tool usage: call counts, patterns, efficiency metrics

4. **Generate markdown report** with these sections:

### Report Structure

```markdown
# KubeVirt [Test Type] Integration Test Results Summary

**Test Run:** [Date and Time] **Test Type:** [Description based on prefix, e.g., "With Pause Tool", "Without Pause Tool", or "All Tests"]

## Executive Summary

[Brief overview paragraph]

### Overall Results by Agent

| Agent | Total Tasks | Passed | Failed | Success Rate |
|-------|-------------|--------|--------|--------------|
| ...   | ...         | ...    | ...    | ...          |

**Overall Success Rate:** X/Y tasks passed (Z%)

---

## Detailed Results by Agent

### 1. [Agent Name] ([version])

**Overall Performance:** X/Y tasks passed (Z%)

#### Task Results

| Task | Difficulty | Result | Issue |
|------|------------|--------|-------|
| ...  | ...        | ...    | ...   |

#### Key Observations

**Strengths:**
- [Bullet points]

**Weaknesses:**
- [Bullet points]

**Tool Usage:**
- [Analysis]

---

[Repeat for each agent]

## Task-by-Task Analysis

### [Task Name] ([Difficulty])

**Success Rate:** X/Y (Z%)

**Common Issues:**
- [Bullet points]

**Key Success Factors:**
- [Bullet points]

---

[Repeat for each task]

## Key Findings

### Critical Issues [With/Without] Specialized Toolset

1. **[Issue Category]**
   - [Details]

### Tool Usage Patterns

**Efficient Agents:**
- [Patterns]

**Inefficient Agents:**
- [Patterns]

---

## Recommendations

1. **For Production Use:**
   - [Recommendations]

2. **For Tool Development:**
   - [Recommendations]

3. **For Agent Improvements:**
   - [Recommendations]

---

## Test Environment

- **Test Date:** [Date]
- **Test Start Time:** [Time]
- **Tools Available:** [List]
- **API Versions:** [Details]
```

## Data Extraction Guide

### File Pattern Matching with Prefix

When a prefix argument is provided, only process files matching `gevals-{prefix}-*-out.json`:
- Prefix `with-pause-tool` → matches `gevals-with-pause-tool-claude-code-TIMESTAMP-out.json`, `gevals-with-pause-tool-gemini-TIMESTAMP-out.json`, etc.
- Prefix `without-pause-tool` → matches `gevals-without-pause-tool-*-out.json`
- No prefix → matches all `gevals-*-out.json` files

### Agent Name Parsing
- `gevals-claude-code-TIMESTAMP-out.json` → "Claude Code"
- `gevals-gemini-TIMESTAMP-out.json` → "Gemini"
- `gevals-openai-agent-MODEL-TIMESTAMP-out.json` → "OpenAI Agent (MODEL)"
- `gevals-with-pause-tool-AGENT-TIMESTAMP-out.json` → Extract AGENT part (e.g., "Claude Code", "Gemini")
- `gevals-{prefix}-AGENT-TIMESTAMP-out.json` → Extract AGENT part after the prefix

### JSON Structure
```json
[
  {
    "taskName": "string",
    "taskPath": "string",
    "taskPassed": boolean,
    "taskOutput": "string",
    "difficulty": "easy|medium|hard",
    "assertionResults": {
      "toolsUsed": { "passed": boolean },
      "minToolCalls": { "passed": boolean },
      "maxToolCalls": { "passed": boolean }
    },
    "allAssertionsPassed": boolean,
    "callHistory": {
      "ToolCalls": [
        {
          "name": "tool_name",
          "success": boolean,
          "timestamp": "ISO-8601"
        }
      ]
    }
  }
]
```

### Key Metrics to Calculate

- **Success Rate**: `(passed_tasks / total_tasks) * 100`
- **Tool Call Count**: `len(callHistory.ToolCalls)`
- **Unique Tools Used**: `set(call.name for call in ToolCalls)`
- **Assertion Pass Rate**: Count of passed assertions / total assertions

## Output Requirements

- Use emoji markers: ✅ PASS, ❌ FAIL
- Format percentages to 1 decimal place
- Include horizontal rules (---) between major sections
- Use tables for statistical data
- Use bullet points for observations and findings
- Include specific examples with data points
- Make insights actionable and specific

## Quality Checklist

Before finalizing the report, ensure:
- [ ] All JSON files have been processed
- [ ] Agent names are correctly formatted
- [ ] All statistics are accurate
- [ ] Each section follows the structure above
- [ ] Examples and specific data points are included
- [ ] Recommendations are actionable
- [ ] Report is similar in quality and format to example.md

Save the final report with an appropriate filename:
- **With prefix**: `kubevirt-test-results-[prefix]-[TIMESTAMP].md` (e.g., `kubevirt-test-results-with-pause-tool-20251112-201350.md`)
- **Without prefix**: `kubevirt-test-results-[TIMESTAMP].md`

Save the file in the current directory.
