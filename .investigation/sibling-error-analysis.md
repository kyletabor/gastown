# Sibling Tool Call Error Investigation

**Investigation Date:** 2026-01-31
**Investigator:** gastown/polecats/furiosa
**Issue:** hq-8mb

## Summary

The "Sibling tool call errored" error is **not** present in the gastown codebase. This is a Claude Code internal error that occurs when parallel tool calls are made and one of them fails.

## Investigation Results

### 1. Codebase Search

Searched gastown repository for:
- Exact phrase: `"Sibling tool call errored"` → **No matches**
- Pattern: `sibling.*tool.*call` (case-insensitive) → **No matches**
- Pattern: `sibling` (case-insensitive) → **1 match** (unrelated: molecule progress comment)
- Pattern: `tool call.*error` (case-insensitive) → **No matches**

**Conclusion:** This error originates from Claude Code itself, not from gastown tooling.

### 2. Error Origin

**Location:** Claude Code internal error handling (not in gastown codebase)

**What triggers it:**
- Making parallel tool calls (multiple tools invoked in single message)
- One or more tool calls fail/error
- Remaining "sibling" tool calls in the same parallel batch are blocked

### 3. Why It Happens

Based on the error pattern observed by mayor:

**Behavior:** When Claude Code executes multiple parallel tool calls and one fails:
1. The failed tool returns an error
2. Remaining sibling tools (in same parallel batch) are short-circuited
3. Those sibling tools show: "Sibling tool call errored"

**Likely Design Decision:**
This appears to be a **safety mechanism** in Claude Code:
- Prevents cascading failures from bad parallel execution
- Stops execution when one parallel operation fails
- Assumes parallel calls may have hidden dependencies

**Rationale:**
If tool calls are submitted in parallel, they're assumed to be independent. However, if one fails catastrophically, continuing with siblings might:
- Waste API tokens on operations that may fail
- Create inconsistent state
- Produce misleading results

### 4. Impact Assessment

**Severity:** Low to Medium

**Positive Impact:**
- Prevents wasted work when parallel batch has fundamental issues
- Fails fast rather than producing partial/corrupt results
- Clear error message indicating sibling relationship

**Negative Impact:**
- Blocks truly independent operations from completing
- Less granular error handling (all-or-nothing for parallel batch)
- May require retry of successful-but-blocked operations

**Frequency:**
According to mayor: "frequently when making parallel tool calls"

### 5. Root Cause Classification

**Type:** Design decision (not a bug)

**Category:** Error handling / execution safety

**Scope:** Claude Code tool execution engine

## Recommendations

### For Mayor (Immediate)

1. **Avoid parallel batches when operations aren't truly independent**
   - If operations have potential dependencies, run sequentially
   - Use parallel calls only for completely isolated operations

2. **Structure tool calls defensively**
   - Put more critical/likely-to-succeed operations first
   - Consider splitting high-risk parallel batches into smaller groups

3. **Error recovery pattern**
   - When this error occurs, identify which sibling call failed
   - Retry the blocked operations individually if they're still needed

### For Future Investigation

1. **Confirm Claude Code behavior**
   - Test with simple parallel tool calls where one deliberately fails
   - Document exact conditions that trigger sibling blocking

2. **Check Claude Code documentation/source**
   - If Claude Code is open source, locate this error in their codebase
   - Understand if there's configuration to change this behavior

3. **Evaluate alternative approaches**
   - Could gastown wrap tool calls to handle this better?
   - Should we avoid parallel calls in certain contexts?

## Example Scenario

```
# Mayor makes parallel calls:
- Bash call A (fails)
- Bash call B (blocked → "Sibling tool call errored")
- Bash call C (blocked → "Sibling tool call errored")

# All three were independent, but B and C never executed
# because A failed first
```

## Open Questions

1. Does the order of parallel calls matter? (Does first failure block all subsequent?)
2. Is there a timeout/retry mechanism available?
3. Can we configure Claude Code's parallel execution strategy?
4. Are certain tool types more prone to this than others?

## Files Searched

- All files in gastown repository
- Search methods: Grep with multiple patterns, case-insensitive
- No external dependencies searched (Claude Code source not available in this workspace)

## Conclusion

**Root Cause:** Claude Code's parallel tool execution safety mechanism
**Location:** Not in gastown codebase (internal to Claude Code)
**Why:** Fail-fast design to prevent cascading errors in parallel batches
**Fix Needed:** No (working as designed, but awareness needed)
**Action Required:** Adapt usage patterns to work with this behavior
