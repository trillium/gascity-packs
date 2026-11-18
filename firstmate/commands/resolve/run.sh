#!/bin/sh
# firstmate resolve - record the captain's answer to a decision and close it.
# Invoked as: gc firstmate resolve ID --answer "the captain's words" [--outcome approve|hold]
#
# Environment (set by gc):
#   GC_BIN    - path to the gc binary (falls back to `gc` on PATH)
#   GC_AGENT  - the calling agent (required: refuses unowned transitions)
#   GC_RIG    - rig scope, when running from a rig agent (optional)
#
# Only beads labeled `firstmate-decision` can be resolved here. The id must
# match exactly: gc bd fuzzy-matches bare ids, so this command looks the id up
# in the ledger listing instead of trusting a direct show/close.

set -eu

LABEL="firstmate-decision"
GC="${GC_BIN:-gc}"
RIG="${GC_RIG:-}"

usage() {
    cat >&2 <<'EOF'
usage: gc firstmate resolve ID --answer "what the captain said" [--outcome approve|hold] [--rig RIG]
EOF
    exit 2
}

die() {
    echo "resolve: $*" >&2
    exit 1
}

gcbd() {
    sub=$1
    shift
    if [ -n "$RIG" ]; then
        "$GC" bd "$sub" --rig="$RIG" "$@"
    else
        "$GC" bd "$sub" "$@"
    fi
}

ID=""
ANSWER=""
OUTCOME=""
while [ $# -gt 0 ]; do
    case "$1" in
        --answer) [ $# -ge 2 ] || usage; ANSWER=$2; shift 2 ;;
        --outcome) [ $# -ge 2 ] || usage; OUTCOME=$2; shift 2 ;;
        --rig)    [ $# -ge 2 ] || usage; RIG=$2; shift 2 ;;
        -h|--help|help) usage ;;
        -*) echo "resolve: unknown argument: $1" >&2; usage ;;
        *)
            [ -z "$ID" ] || usage
            ID=$1
            shift
            ;;
    esac
done

[ -n "$ID" ] || usage
[ -n "${GC_AGENT:-}" ] || die "GC_AGENT is empty; refusing an unowned state transition"
if [ -z "$(printf '%s' "$ANSWER" | tr -d '[:space:]')" ]; then
    die "--answer is required: record what the captain actually said, in their words"
fi
command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"

listing=$(gcbd list --label "$LABEL" --all --json --limit 0) \
    || die "could not read the ledger"
[ -n "$listing" ] || die "ledger read returned nothing (is the store reachable?)"

decision=$(printf '%s' "$listing" | jq -c --arg id "$ID" '
    if type != "array" then error("unexpected ledger payload")
    else (map(select(.id == $id)) | .[0] // null) end') \
    || die "unexpected ledger payload"

status=$(printf '%s' "$decision" | jq -r '.status // empty') \
    || die "unexpected decision payload"

case "$status" in
    "")     die "'$ID' is not a decision in the ledger (exact id required); run 'gc firstmate decide list'" ;;
    closed) die "'$ID' is already resolved; its recorded answer is in its comments (gc bd comments $ID)" ;;
esac

is_merge=$(printf '%s' "$decision" | jq -r '
    (.labels // []) as $labels |
    if ($labels | type) == "array" then ($labels | index("decision-kind:merge") != null)
    else ($labels | tostring | contains("decision-kind:merge"))
    end') || die "unexpected decision labels"

case "$is_merge" in
    true)
        case "$OUTCOME" in
            approve|hold) ;;
            "") die "--outcome approve|hold is required for a merge decision" ;;
            *) die "--outcome must be approve or hold for a merge decision" ;;
        esac
        ;;
    false) [ -z "$OUTCOME" ] || die "--outcome applies only to merge decisions" ;;
    *) die "unexpected decision labels" ;;
esac

# Record the answer first, so a failed close still leaves the answer on file.
comment="ANSWER (from the captain, recorded by $GC_AGENT): $ANSWER"
if [ "$is_merge" = true ]; then
    comment="$comment
OUTCOME: $OUTCOME"
fi
gcbd comment "$ID" "$comment" \
    || die "could not record the answer on '$ID'; nothing was closed"

short=$(printf '%s' "$ANSWER" | head -n 1 | cut -c1-120)
reason="resolved by the captain: $short"
if [ "$is_merge" = true ]; then
    reason="$reason (outcome: $OUTCOME)"
fi
if ! gcbd close "$ID" --reason "$reason"; then
    die "answer and outcome recorded on '$ID' but closing it failed; retry: gc bd close $ID"
fi

echo "DECISION RESOLVED: $ID"
echo "Recorded answer: $ANSWER"
if [ "$is_merge" = true ]; then
    echo "Recorded outcome: $OUTCOME"
fi
echo "Now act on it, and tell the captain what changed (outcome first)."
