#!/bin/sh

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT/firstmate/commands/resolve/run.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT HUP INT TERM
FAKE_DIR="$TMPDIR/store"
mkdir -p "$FAKE_DIR"
export FAKE_DIR
cp "$ROOT/tests/fake-gc.sh" "$TMPDIR/gc"

run() {
    GC_BIN="$TMPDIR/gc" GC_AGENT=mayor "$SCRIPT" "$@"
}

expect_refusal() {
    expected=$1
    shift
    if output=$(run "$@" 2>&1); then
        echo "expected refusal, got success: $output" >&2
        exit 1
    fi
    case "$output" in
        *"$expected"*) ;;
        *) echo "expected '$expected', got: $output" >&2; exit 1 ;;
    esac
}

BASE='{"title":"t","metadata":{},"comments":[]}'
{
    printf '[%s,\n' "$(printf '%s' "$BASE" | jq -c '. + {id:"d-approve",status:"open",labels:["firstmate-decision","decision-kind:approve"]}')"
    printf '%s,\n' "$(printf '%s' "$BASE" | jq -c '. + {id:"d-closed",status:"closed",labels:["firstmate-decision","decision-kind:merge","decision-work:w-1"]}')"
    printf '%s]\n' "$(printf '%s' "$BASE" | jq -c '. + {id:"d-nowork",status:"open",labels:["firstmate-decision","decision-kind:merge"]}')"
} >"$FAKE_DIR/beads.json"

expect_refusal 'not a decision in the ledger' missing --answer 'no' --outcome hold
expect_refusal 'already resolved' d-closed --answer 'merge it' --outcome approve --captain trillium
expect_refusal 'names no work bead' d-nowork --answer 'merge it' --outcome approve --captain trillium
expect_refusal '--outcome applies only to merge decisions' d-approve --answer 'yes' --outcome approve
expect_refusal '--captain applies only to merge decisions' d-approve --answer 'yes' --captain trillium
expect_refusal '--answer is required' d-approve --answer ' '

output=$(run d-approve --answer 'yes')
case "$output" in
    *'DECISION RESOLVED: d-approve'*'Now act on it, and tell the captain what changed (outcome first).'*'Recorded outcome:'*) echo "non-merge resolution included outcome guidance: $output" >&2; exit 1 ;;
    *'DECISION RESOLVED: d-approve'*'Now act on it, and tell the captain what changed (outcome first).'*) ;;
    *) echo "non-merge resolution did not provide ordinary guidance: $output" >&2; exit 1 ;;
esac
jq -e 'map(select(.id == "d-approve")) | .[0] | .status == "closed" and (.comments | length == 1)' "$FAKE_DIR/beads.json" >/dev/null

# Merge resolution (captain binding, work flag, live head) is covered end to
# end in merge-gate-command.sh.
