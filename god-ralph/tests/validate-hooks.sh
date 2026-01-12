#!/bin/bash
#
# Validation tests for god-ralph hooks (Updated for per-bead architecture)
# Run from the god-ralph plugin directory
#
# Usage: ./tests/validate-hooks.sh
#
# Tests the new per-bead session/queue file architecture:
# - Spawn queue files: .claude/god-ralph/spawn-queue/<bead-id>.json
# - Session files: .claude/god-ralph/sessions/<bead-id>.json
# - Marker files: {worktree}/.claude/god-ralph/current-bead
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR=$(mktemp -d)
PASS_COUNT=0
FAIL_COUNT=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

log_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    echo "  Expected: $2"
    echo "  Got: $3"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

log_info() {
    echo -e "${YELLOW}→${NC} $1"
}

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "=========================================="
echo "God-Ralph Hook Validation Tests"
echo "(Per-Bead Session Architecture)"
echo "=========================================="
echo ""
echo "Test directory: $TEST_DIR"
echo ""

# Initialize a test git repo
cd "$TEST_DIR"
git init -q
echo "test" > test.txt
git add test.txt
git commit -q -m "Initial commit"

# =============================================================================
# TEST 1: ensure-worktree.sh - BEAD_ID extraction (macOS compatible)
# =============================================================================
echo ""
echo "--- Test 1: BEAD_ID Extraction (macOS-compatible grep -E) ---"

log_info "Testing BEAD_ID: marker extraction..."

# First create spawn queue file
mkdir -p .claude/god-ralph/spawn-queue
cat > .claude/god-ralph/spawn-queue/beads-abc123.json << 'EOF'
{
  "worktree_path": ".worktrees/ralph-beads-abc123",
  "worktree_policy": "required",
  "max_iterations": 10,
  "completion_promise": "BEAD COMPLETE"
}
EOF

MOCK_INPUT='{
  "tool_name": "Task",
  "tool_input": {
    "subagent_type": "ralph-worker",
    "description": "Ralph worker for beads-abc123",
    "prompt": "BEAD_ID: beads-abc123\n\nYou are working on bead: beads-abc123"
  }
}'

# Capture output
OUTPUT=$( (echo "$MOCK_INPUT" | "$PLUGIN_ROOT/hooks/ensure-worktree.sh") 2>>"$TEST_DIR/hook.log" ) || true

# Check for success
PERMISSION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || echo "")

if [[ "$PERMISSION" == "allow" ]]; then
    log_pass "BEAD_ID 'beads-abc123' extracted and worktree created"
else
    REASON=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null || echo "$OUTPUT")
    log_fail "BEAD_ID extraction" "allow" "Permission: $PERMISSION, Reason: $REASON"
fi

# =============================================================================
# TEST 2: Per-bead session file creation
# =============================================================================
echo ""
echo "--- Test 2: Per-Bead Session File Creation ---"

log_info "Checking session file at .claude/god-ralph/sessions/beads-abc123.json..."

if [[ -f ".claude/god-ralph/sessions/beads-abc123.json" ]]; then
    log_pass "Session file created at sessions/beads-abc123.json"

    # Verify session file contents
    BEAD_ID_IN_SESSION=$(jq -r '.bead_id' .claude/god-ralph/sessions/beads-abc123.json 2>/dev/null || echo "")
    if [[ "$BEAD_ID_IN_SESSION" == "beads-abc123" ]]; then
        log_pass "Session file contains correct bead_id"
    else
        log_fail "Session file bead_id" "beads-abc123" "$BEAD_ID_IN_SESSION"
    fi

    STATUS=$(jq -r '.status' .claude/god-ralph/sessions/beads-abc123.json 2>/dev/null || echo "")
    if [[ "$STATUS" == "in_progress" ]]; then
        log_pass "Session status is 'in_progress'"
    else
        log_fail "Session status" "in_progress" "$STATUS"
    fi
else
    log_fail "Session file creation" "exists" "not found"
fi

# =============================================================================
# TEST 3: Worktree marker file creation
# =============================================================================
echo ""
echo "--- Test 3: Worktree Marker File Creation ---"

log_info "Checking marker file in worktree..."

MARKER_FILE=".worktrees/ralph-beads-abc123/.claude/god-ralph/current-bead"
if [[ -f "$MARKER_FILE" ]]; then
    MARKER_CONTENT=$(cat "$MARKER_FILE")
    if [[ "$MARKER_CONTENT" == "beads-abc123" ]]; then
        log_pass "Marker file contains correct bead_id"
    else
        log_fail "Marker file content" "beads-abc123" "$MARKER_CONTENT"
    fi
else
    log_fail "Marker file creation" "exists" "not found at $MARKER_FILE"
fi

# =============================================================================
# TEST 4: Spawn queue file cleanup
# =============================================================================
echo ""
echo "--- Test 4: Spawn Queue File Cleanup ---"

log_info "Checking spawn queue file was removed..."

if [[ ! -f ".claude/god-ralph/spawn-queue/beads-abc123.json" ]]; then
    log_pass "Spawn queue file removed after worktree creation"
else
    log_fail "Spawn queue cleanup" "removed" "still exists"
fi

# =============================================================================
# TEST 5: ralph-stop-hook.sh - Promise detection
# =============================================================================
echo ""
echo "--- Test 5: Ralph Stop Hook Promise Detection ---"

log_info "Testing promise detection in transcript..."

# Create mock transcript with promise
mkdir -p "$TEST_DIR/transcripts"
TRANSCRIPT_FILE="$TEST_DIR/transcripts/test-transcript.jsonl"

cat > "$TRANSCRIPT_FILE" << 'TRANSCRIPT'
{"role": "user", "content": "Continue working"}
{"role": "assistant", "content": "I have completed all acceptance criteria.\n\n<promise>BEAD COMPLETE</promise>"}
TRANSCRIPT

# cd to worktree context for stop hook
cd ".worktrees/ralph-beads-abc123"

STOP_INPUT="{\"transcript_path\": \"$TRANSCRIPT_FILE\"}"
STOP_OUTPUT=$(echo "$STOP_INPUT" | "$PLUGIN_ROOT/hooks/ralph-stop-hook.sh" 2>/dev/null; echo "EXIT_CODE:$?")
STOP_EXIT=$(echo "$STOP_OUTPUT" | grep -o 'EXIT_CODE:[0-9]*' | cut -d: -f2)

if [[ "$STOP_EXIT" == "0" ]]; then
    log_pass "Promise '<promise>BEAD COMPLETE</promise>' detected correctly"
else
    log_fail "Promise detection" "exit 0 (promise found)" "exit $STOP_EXIT"
fi

# Check session was updated to completed
cd "$TEST_DIR"
SESSION_STATUS=$(jq -r '.status' .claude/god-ralph/sessions/beads-abc123.json 2>/dev/null || echo "")
if [[ "$SESSION_STATUS" == "completed" ]]; then
    log_pass "Session status updated to 'completed'"
else
    log_fail "Session status update" "completed" "$SESSION_STATUS"
fi

# =============================================================================
# TEST 6: ralph-stop-hook.sh - Iteration increment
# =============================================================================
echo ""
echo "--- Test 6: Stop Hook Iteration Increment ---"

log_info "Testing iteration increment on incomplete work..."

# Reset session for test
cat > ".claude/god-ralph/sessions/beads-abc123.json" << 'STATE'
{
  "bead_id": "beads-abc123",
  "worktree_path": ".worktrees/ralph-beads-abc123",
  "status": "in_progress",
  "iteration": 3,
  "max_iterations": 10,
  "completion_promise": "BEAD COMPLETE",
  "created_at": "2024-01-10T00:00:00Z",
  "updated_at": "2024-01-10T00:00:00Z"
}
STATE

# Transcript without promise
cat > "$TRANSCRIPT_FILE" << 'TRANSCRIPT'
{"role": "assistant", "content": "Still working on it..."}
TRANSCRIPT

cd ".worktrees/ralph-beads-abc123"
STOP_OUTPUT2=$(echo "$STOP_INPUT" | "$PLUGIN_ROOT/hooks/ralph-stop-hook.sh" 2>/dev/null || true)
cd "$TEST_DIR"

# Check iteration was incremented
NEW_ITERATION=$(jq -r '.iteration' .claude/god-ralph/sessions/beads-abc123.json 2>/dev/null || echo "")
if [[ "$NEW_ITERATION" == "4" ]]; then
    log_pass "Iteration incremented from 3 to 4"
else
    log_fail "Iteration increment" "4" "$NEW_ITERATION"
fi

# Check block decision was returned
DECISION=$(echo "$STOP_OUTPUT2" | jq -r '.decision // empty' 2>/dev/null || echo "")
if [[ "$DECISION" == "block" ]]; then
    log_pass "Stop hook returned block decision for incomplete work"
else
    log_fail "Block decision" "block" "$DECISION"
fi

# =============================================================================
# TEST 7: ralph-stop-hook.sh - Max iterations
# =============================================================================
echo ""
echo "--- Test 7: Max Iterations Exit ---"

log_info "Testing max iterations handling..."

cat > ".claude/god-ralph/sessions/beads-abc123.json" << 'STATE'
{
  "bead_id": "beads-abc123",
  "worktree_path": ".worktrees/ralph-beads-abc123",
  "status": "in_progress",
  "iteration": 10,
  "max_iterations": 10,
  "completion_promise": "BEAD COMPLETE"
}
STATE

cat > "$TRANSCRIPT_FILE" << 'TRANSCRIPT'
{"role": "assistant", "content": "Still not done..."}
TRANSCRIPT

cd ".worktrees/ralph-beads-abc123"
STOP_OUTPUT3=$(echo "$STOP_INPUT" | "$PLUGIN_ROOT/hooks/ralph-stop-hook.sh" 2>/dev/null; echo "EXIT_CODE:$?")
STOP_EXIT3=$(echo "$STOP_OUTPUT3" | grep -o 'EXIT_CODE:[0-9]*' | cut -d: -f2)
cd "$TEST_DIR"

if [[ "$STOP_EXIT3" == "0" ]]; then
    log_pass "Max iterations (10/10) allows exit"
else
    log_fail "Max iterations exit" "exit 0" "exit $STOP_EXIT3"
fi

# Check status was updated to failed
STATUS=$(jq -r '.status' .claude/god-ralph/sessions/beads-abc123.json 2>/dev/null || echo "")
if [[ "$STATUS" == "failed" ]]; then
    log_pass "Status updated to 'failed' on max iterations"
else
    log_fail "Failed status" "failed" "$STATUS"
fi

# =============================================================================
# TEST 8: ensure-worktree.sh - Missing spawn queue file
# =============================================================================
echo ""
echo "--- Test 8: Missing Spawn Queue File Denied ---"

log_info "Testing denial when spawn queue file missing..."

MOCK_INPUT_NO_QUEUE='{
  "tool_name": "Task",
  "tool_input": {
    "subagent_type": "ralph-worker",
    "description": "Ralph worker for beads-xyz999",
    "prompt": "BEAD_ID: beads-xyz999\n\nWork on this bead"
  }
}'

OUTPUT_NO_QUEUE=$( (echo "$MOCK_INPUT_NO_QUEUE" | "$PLUGIN_ROOT/hooks/ensure-worktree.sh") 2>/dev/null ) || true
PERMISSION_NO_QUEUE=$(echo "$OUTPUT_NO_QUEUE" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || echo "")

if [[ "$PERMISSION_NO_QUEUE" == "deny" ]]; then
    log_pass "Missing spawn queue file correctly denied"
else
    log_fail "Missing queue denial" "deny" "$PERMISSION_NO_QUEUE"
fi

# =============================================================================
# TEST 9: Non-ralph-worker agents passthrough
# =============================================================================
echo ""
echo "--- Test 9: Non-Worker Agent Passthrough ---"

log_info "Testing that non-worker agents skip worktree creation..."

MOCK_INPUT_SCRIBE='{
  "tool_name": "Task",
  "tool_input": {
    "subagent_type": "scribe",
    "description": "Update CLAUDE.md",
    "prompt": "Log this learning"
  }
}'

OUTPUT_SCRIBE=$(echo "$MOCK_INPUT_SCRIBE" | "$PLUGIN_ROOT/hooks/ensure-worktree.sh" 2>/dev/null || true)
PERMISSION=$(echo "$OUTPUT_SCRIBE" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || echo "")

if [[ "$PERMISSION" == "allow" ]]; then
    # Check no updatedInput (passthrough)
    UPDATED=$(echo "$OUTPUT_SCRIBE" | jq -r '.hookSpecificOutput.updatedInput // "none"' 2>/dev/null || echo "")
    if [[ "$UPDATED" == "none" ]] || [[ "$UPDATED" == "null" ]]; then
        log_pass "Non-worker agent 'scribe' passed through without worktree"
    else
        log_fail "Non-worker passthrough" "no updatedInput" "got updatedInput"
    fi
else
    log_fail "Non-worker permission" "allow" "$PERMISSION"
fi

# =============================================================================
# TEST 10: cleanup-worktree.sh --status
# =============================================================================
echo ""
echo "--- Test 10: Cleanup Script Status ---"

log_info "Testing cleanup script --status..."

STATUS_OUTPUT=$("$PLUGIN_ROOT/scripts/cleanup-worktree.sh" --status 2>&1 || true)

if echo "$STATUS_OUTPUT" | grep -q "Ralph Worktree Status"; then
    log_pass "Cleanup script --status runs without error"
else
    log_fail "Cleanup --status" "Status output" "$STATUS_OUTPUT"
fi

# =============================================================================
# TEST 11: Parallel session isolation
# =============================================================================
echo ""
echo "--- Test 11: Parallel Session Isolation ---"

log_info "Testing that parallel beads have separate session files..."

# Create second spawn queue
mkdir -p .claude/god-ralph/spawn-queue
cat > .claude/god-ralph/spawn-queue/beads-second.json << 'EOF'
{
  "worktree_path": ".worktrees/ralph-beads-second",
  "worktree_policy": "required",
  "max_iterations": 5,
  "completion_promise": "SECOND COMPLETE"
}
EOF

MOCK_INPUT_SECOND='{
  "tool_name": "Task",
  "tool_input": {
    "subagent_type": "ralph-worker",
    "description": "Ralph worker for beads-second",
    "prompt": "BEAD_ID: beads-second\n\nWork on second bead"
  }
}'

OUTPUT_SECOND=$( (echo "$MOCK_INPUT_SECOND" | "$PLUGIN_ROOT/hooks/ensure-worktree.sh") 2>/dev/null ) || true

# Check both session files exist and are different
if [[ -f ".claude/god-ralph/sessions/beads-abc123.json" ]] && [[ -f ".claude/god-ralph/sessions/beads-second.json" ]]; then
    FIRST_PROMISE=$(jq -r '.completion_promise' .claude/god-ralph/sessions/beads-abc123.json 2>/dev/null || echo "")
    SECOND_PROMISE=$(jq -r '.completion_promise' .claude/god-ralph/sessions/beads-second.json 2>/dev/null || echo "")

    if [[ "$FIRST_PROMISE" == "BEAD COMPLETE" ]] && [[ "$SECOND_PROMISE" == "SECOND COMPLETE" ]]; then
        log_pass "Parallel beads have separate session files with different promises"
    else
        log_fail "Parallel session isolation" "different promises" "first: $FIRST_PROMISE, second: $SECOND_PROMISE"
    fi
else
    log_fail "Parallel session files" "both exist" "one or both missing"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review.${NC}"
    exit 1
fi
