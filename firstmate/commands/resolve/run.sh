#!/bin/sh
# shellcheck disable=SC2034  # CMD, GC and RIG are read by the sourced gate-lib.sh
# firstmate resolve - record the captain's answer to a decision and close it.
# Invoked as: gc firstmate resolve ID --answer "the captain's words" [--outcome OUTCOME]
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

CMD="resolve"
LABEL="firstmate-decision"
GC="${GC_BIN:-gc}"
RIG="${GC_RIG:-}"

LIB="${GC_PACK_DIR:+$GC_PACK_DIR/assets/lib/gate-lib.sh}"
[ -f "${LIB:-}" ] || LIB="$(dirname -- "$0")/../../assets/lib/gate-lib.sh"
# shellcheck disable=SC1090
. "$LIB"

usage() {
    cat >&2 <<'EOF'
usage: gc firstmate resolve ID --answer "what the captain said" [--outcome OUTCOME] [--captain CAPTAIN_ID] [--rig RIG]
(a merge decision requires --outcome approve|hold and --captain, the bound captain's id)
EOF
    exit 2
}

ID=""
ANSWER=""
OUTCOME=""
CAPTAIN=""
while [ $# -gt 0 ]; do
    case "$1" in
        --answer) [ $# -ge 2 ] || usage; ANSWER=$2; shift 2 ;;
        --outcome) [ $# -ge 2 ] || usage; OUTCOME=$2; shift 2 ;;
        --captain) [ $# -ge 2 ] || usage; CAPTAIN=$2; shift 2 ;;
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
need_jq

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

WORK=""
HEAD=""
case "$is_merge" in
    true)
        case "$OUTCOME" in
            approve|hold) ;;
            "") die "--outcome is required for a merge decision; use approve or hold" ;;
            *) die "--outcome must be approve or hold for a merge decision" ;;
        esac
        # A merge decision is bound to exactly one work bead (set by decide
        # --blocks) and may only be resolved as the bound captain.
        WORK=$(printf '%s' "$decision" | jq -r '
            [(.labels // [])[] | select(startswith("decision-work:")) | sub("^decision-work:"; "")] | .[0] // empty') \
            || die "unexpected decision labels"
        [ -n "$WORK" ] || die "'$ID' names no work bead (it was filed without --blocks); it cannot authorize a merge"
        bound=$(bound_captain)
        [ -n "$bound" ] || die "no captain is bound; run 'gc firstmate merge-gate bind-captain --id <captain>' first"
        [ -n "$CAPTAIN" ] || die "--captain is required for a merge decision (the bound captain's id)"
        [ "$CAPTAIN" = "$bound" ] || die "--captain '$CAPTAIN' is not the bound captain; refusing"
        bead=$(work_bead "$WORK")
        if [ "$OUTCOME" = approve ]; then
            [ "$(printf '%s' "$bead" | jq -r '.status // empty')" != closed ] \
                || die "work bead $WORK is already closed; nothing to authorize"
            HEAD=$(live_state "$bead" | jq -r '.head // empty') || die "could not read the live head of $WORK"
            [ -n "$HEAD" ] || die "live head of $WORK is empty; refusing to approve an unpinned change"
        fi
        ;;
    false)
        [ -z "$OUTCOME" ] || die "--outcome applies only to merge decisions"
        [ -z "$CAPTAIN" ] || die "--captain applies only to merge decisions"
        ;;
    *) die "unexpected decision labels" ;;
esac

# Record the answer first, so a failed close still leaves the answer on file.
comment="ANSWER (from the captain, recorded by $GC_AGENT): $ANSWER"
if [ "$is_merge" = true ]; then
    comment="$comment
OUTCOME: $OUTCOME
CAPTAIN: $CAPTAIN
WORK: $WORK"
    [ -z "$HEAD" ] || comment="$comment
HEAD: $HEAD"
fi
gcbd comment "$ID" "$comment" \
    || die "could not record the answer on '$ID'; nothing was closed"

# Persist the per-work-bead merge-authority flag before closing, so a closed
# approval always has its flag and a failed write leaves the decision open.
if [ "$is_merge" = true ]; then
    if [ "$OUTCOME" = approve ]; then
        gcbd update "$WORK" --set-metadata merge_authority=approved \
            --set-metadata "merge_authority_decision=$ID" \
            --set-metadata "merge_authority_captain=$CAPTAIN" \
            --set-metadata "merge_authority_head=$HEAD" >/dev/null \
            || die "answer recorded on '$ID' but the merge-authority flag on $WORK was not set; retry the resolve"
    else
        gcbd update "$WORK" --set-metadata merge_authority=held \
            --set-metadata "merge_authority_decision=$ID" >/dev/null \
            || die "answer recorded on '$ID' but the hold flag on $WORK was not set; retry the resolve"
    fi
fi

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
case "$is_merge:$OUTCOME" in
    true:approve) echo "Approval recorded: $WORK may land at $HEAD, only through: gc firstmate merge-gate land $WORK -- <landing command>" ;;
    true:hold) echo "Hold recorded: keep this change unlanded and stop." ;;
    false:) echo "Now act on it, and tell the captain what changed (outcome first)." ;;
esac
