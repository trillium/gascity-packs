#!/bin/sh

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT/firstmate/commands/resolve/run.sh"
TMPDIR=$(mktemp -d)
LOG="$TMPDIR/gc.log"
trap 'rm -rf "$TMPDIR"' EXIT HUP INT TERM

cat >"$TMPDIR/gc" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = bd ]
case "$2" in
    list) printf '%s\n' "$LEDGER_JSON" ;;
    comment|close) printf '%s\n' "$*" >>"$GC_LOG" ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$TMPDIR/gc"

run() {
    ledger=$1
    shift
    LEDGER_JSON="$ledger" GC_LOG="$LOG" GC_BIN="$TMPDIR/gc" GC_AGENT=mayor "$SCRIPT" "$@"
}

expect_refusal() {
    expected=$1
    ledger=$2
    shift 2
    if output=$(run "$ledger" "$@" 2>&1); then
        echo "expected refusal, got success: $output" >&2
        exit 1
    fi
    case "$output" in
        *"$expected"*) ;;
        *) echo "expected '$expected', got: $output" >&2; exit 1 ;;
    esac
}

MERGE_OPEN='[{"id":"d-merge","status":"open","labels":["firstmate-decision","decision-kind:merge"]}]'
MERGE_CLOSED='[{"id":"d-merge","status":"closed","labels":["firstmate-decision","decision-kind:merge"]}]'
APPROVE_OPEN='[{"id":"d-approve","status":"open","labels":["firstmate-decision","decision-kind:approve"]}]'

expect_refusal 'not a decision in the ledger' '[]' missing --answer 'no' --outcome hold
expect_refusal '--outcome is required' "$MERGE_OPEN" d-merge --answer 'hold it'
expect_refusal '--outcome must be approve or hold' "$MERGE_OPEN" d-merge --answer 'merge it' --outcome later
expect_refusal 'already resolved' "$MERGE_CLOSED" d-merge --answer 'merge it' --outcome approve

: >"$LOG"
output=$(run "$MERGE_OPEN" d-merge --answer 'hold it' --outcome hold)
case "$output" in
    *'DECISION RESOLVED: d-merge'*'Recorded outcome: hold'*'Hold recorded: keep this change unlanded and stop.'*) ;;
    *) echo "hold outcome was not recorded: $output" >&2; exit 1 ;;
esac
grep -F 'OUTCOME: hold' "$LOG" >/dev/null

: >"$LOG"
output=$(run "$MERGE_OPEN" d-merge --answer 'merge it' --outcome approve)
case "$output" in
    *'DECISION RESOLVED: d-merge'*'Recorded outcome: approve'*'Approval recorded: this exact change may proceed to landing.'*) ;;
    *) echo "approve outcome was not recorded: $output" >&2; exit 1 ;;
esac
grep -F 'OUTCOME: approve' "$LOG" >/dev/null

output=$(run "$APPROVE_OPEN" d-approve --answer 'yes')
case "$output" in
    *'DECISION RESOLVED: d-approve'*'Now act on it, and tell the captain what changed (outcome first).'*'Recorded outcome:'*) echo "non-merge resolution included outcome guidance: $output" >&2; exit 1 ;;
    *'DECISION RESOLVED: d-approve'*'Now act on it, and tell the captain what changed (outcome first).'*) ;;
    *) echo "non-merge resolution did not provide ordinary guidance: $output" >&2; exit 1 ;;
esac
