# Shared helpers for the merge gate. Sourced (not executed) by
# commands/resolve/run.sh and commands/merge-gate/run.sh.
#
# The sourcing script sets before use:  CMD (name for messages), GC, RIG.
# Every helper that fails prints "$CMD: <why>" and exits non-zero, so a gate
# that cannot read what it needs refuses instead of passing.

CAPTAIN_LABEL="firstmate-captain"

die() {
    echo "$CMD: $*" >&2
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

need_jq() {
    command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"
}

# bound_captain - print the bound captain identity, or nothing when none is
# bound. Dies when the binding is unreadable or ambiguous.
bound_captain() {
    out=$(gcbd list --label "$CAPTAIN_LABEL" --json --limit 0) \
        || die "could not read the captain binding"
    [ -n "$out" ] || die "captain binding read returned nothing (is the store reachable?)"
    printf '%s' "$out" | jq -r '
        if type != "array" then error("unexpected captain payload")
        else
            [ .[] | select(.status != "closed") | (.labels // [])[]
              | select(startswith("captain-id:")) | sub("^captain-id:"; "") ] as $ids
            | if ($ids | length) > 1 then error("more than one captain bound")
              elif ($ids | length) == 1 then $ids[0]
              else empty end
        end' || die "unexpected captain binding payload"
}

# work_bead ID - print the work bead as one JSON object. The id must match
# exactly (gc bd fuzzy-matches bare ids).
work_bead() {
    out=$(gcbd show "$1" --json) || die "could not read work bead '$1'"
    [ -n "$out" ] || die "work bead read returned nothing for '$1'"
    printf '%s' "$out" | jq -ce --arg id "$1" '
        (if type == "array" then .[0] else . end) as $b
        | if ($b | type) == "object" and $b.id == $id then $b
          else error("no exact match") end' \
        || die "'$1' is not a work bead (exact id required)"
}

# live_state WORK_JSON - print one JSON object describing the change as it is
# right now: {head, open, ready, checks_ok, source}. Reads GitHub for a PR
# (metadata.pr_url, else metadata.existing_pr) and `git ls-remote` for a
# bare branch. Dies when the live state cannot be read.
live_state() {
    pr=$(printf '%s' "$1" | jq -r '.metadata.pr_url // .metadata.existing_pr // empty')
    if [ -n "$pr" ]; then
        case "$pr" in
            https://*) ;;
            *) die "work bead PR reference '$pr' is not a full https URL" ;;
        esac
        raw=$("${GH_BIN:-gh}" pr view "$pr" --json state,isDraft,headRefOid,statusCheckRollup) \
            || die "could not read live PR state for $pr"
        printf '%s' "$raw" | jq -ce '
            {head: .headRefOid, open: (.state == "OPEN"), ready: (.isDraft == false),
             checks_ok: ([(.statusCheckRollup // [])[]
                | (.conclusion // .state // "") | ascii_upcase
                | select(. != "SUCCESS" and . != "NEUTRAL" and . != "SKIPPED")] | length == 0),
             source: "pull request"}' \
            || die "unexpected live PR payload for $pr"
        return 0
    fi
    branch=$(printf '%s' "$1" | jq -r '.metadata.branch // empty')
    [ -n "$branch" ] || die "work bead has neither pr_url nor branch metadata; no live state to check"
    raw=$("${GIT_BIN:-git}" ls-remote origin "refs/heads/$branch") \
        || die "could not read live head of branch '$branch'"
    sha=$(printf '%s\n' "$raw" | awk 'NR==1 {print $1}')
    [ -n "$sha" ] || die "branch '$branch' not found on origin"
    jq -cn --arg head "$sha" '{head: $head, open: true, ready: true, checks_ok: true, source: "branch"}'
}
