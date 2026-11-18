#!/bin/sh
# firstmate decide - file a captain-needed decision in the decision ledger.
# Invoked as: gc firstmate decide [list [--all] | --kind K --what ... ]
#
# Environment (set by gc):
#   GC_BIN         - path to the gc binary (falls back to `gc` on PATH)
#   GC_AGENT       - the calling agent (required: refuses unowned filings)
#   GC_RIG         - rig scope, when running from a rig agent (optional)
#   GC_CITY_PATH, GC_PACK_DIR, GC_CITY_NAME - see gc docs
#
# A decision is a bead labeled `firstmate-decision` whose description holds
# five fields: WHAT / WHAT YOU DO / WHY BLOCKED / ARTIFACT / STAKES.
# `gc firstmate resolve` records the captain's answer and closes it.

set -eu

LABEL="firstmate-decision"
GC="${GC_BIN:-gc}"
RIG="${GC_RIG:-}"
BINDING="firstmate"

usage() {
    cat >&2 <<'EOF'
usage:
  gc firstmate decide --kind approve|merge|pick --what TEXT --you-do TEXT \
      --why-blocked TEXT --artifact TEXT --stakes TEXT \
      --key KEY [--binding BINDING] [--blocks WORK_BEAD_ID] [--rig RIG]
  gc firstmate decide list [--all] [--rig RIG]
EOF
    exit 2
}

die() {
    echo "decide: $*" >&2
    exit 1
}

# gcbd SUBCOMMAND ARGS... - run `gc bd SUBCOMMAND`, scoped to the rig if set.
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

# need_value FLAG COUNT - fail when a flag is missing its value.
need_value() {
    [ "$2" -ge 2 ] || { echo "decide: $1 needs a value" >&2; usage; }
}

blank() {
    # true when the value is empty or whitespace only
    [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]
}

bare_pr_reference() {
    printf '%s' "$1" | sed 's#https://[^[:space:]]*# #g' | grep -Eq '(^|[^[:alnum:]_])#[0-9]+|(^|[[:space:]])[A-Za-z0-9_-]+/[A-Za-z0-9._-]+#[0-9]+([[:space:].,?)]|$)|(^|[^[:alnum:]_])[Pp][Rr]([^[:alnum:]_]|$)|[Pp]ull[[:space:]]+[Rr]equest([^[:alnum:]_]|$)'
}

pr_url_without_https() {
    printf '%s\n' "$1" | awk '
        {
            rest = $0
            while (match(rest, /[^[:space:]]*\/pull\/[0-9]+/)) {
                url = substr(rest, RSTART, RLENGTH)
                if (url !~ /^https:\/\//) {
                    bad = 1
                    exit
                }
                rest = substr(rest, RSTART + RLENGTH)
            }
        }
        END { exit bad ? 0 : 1 }
    '
}

# ---- list ------------------------------------------------------------------

do_list() {
    all=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --all) all="--all"; shift ;;
            --rig) need_value "$1" "$#"; RIG=$2; shift 2 ;;
            *) usage ;;
        esac
    done
    need_jq
    # shellcheck disable=SC2086 # $all is empty or exactly one flag
    out=$(gcbd list --label "$LABEL" $all --json --limit 0) || die "could not read the ledger"
    [ -n "$out" ] || die "ledger read returned nothing (is the store reachable?)"
    printf '%s' "$out" | jq -r '
        if (type != "array") then error("unexpected ledger payload")
        elif length == 0 then "no decisions waiting"
        else sort_by(.created_at // "") | .[] | "\(.id)\t\(.status)\t\(.title)"
        end'
}

# ---- file ------------------------------------------------------------------

case "${1:-}" in
    list) shift; do_list "$@"; exit 0 ;;
    -h|--help|help) usage ;;
esac

KIND=""; WHAT=""; YOU_DO=""; WHY=""; ARTIFACT=""; STAKES=""; KEY=""; BLOCKS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --kind)        need_value "$1" "$#"; KIND=$2; shift 2 ;;
        --what)        need_value "$1" "$#"; WHAT=$2; shift 2 ;;
        --you-do)      need_value "$1" "$#"; YOU_DO=$2; shift 2 ;;
        --why-blocked) need_value "$1" "$#"; WHY=$2; shift 2 ;;
        --artifact)    need_value "$1" "$#"; ARTIFACT=$2; shift 2 ;;
        --stakes)      need_value "$1" "$#"; STAKES=$2; shift 2 ;;
        --key)         need_value "$1" "$#"; KEY=$2; shift 2 ;;
        --binding)     need_value "$1" "$#"; BINDING=$2; shift 2 ;;
        --blocks)      need_value "$1" "$#"; BLOCKS=$2; shift 2 ;;
        --rig)         need_value "$1" "$#"; RIG=$2; shift 2 ;;
        *) echo "decide: unknown argument: $1" >&2; usage ;;
    esac
done

case "$(printf '%s' "$WHAT" | sed 's/[[:space:]]*$//')" in
    *\?) ;;
    *) die "WHAT (--what) must end with a question mark" ;;
esac

[ -n "${GC_AGENT:-}" ] || die "GC_AGENT is empty; refusing an unowned filing"

# The kind vocabulary is closed. Anything else is not a captain decision.
case "$KIND" in
    approve|merge|pick) ;;
    "") echo "decide: --kind is required (approve, merge, or pick)" >&2; usage ;;
    *) die "--kind must be approve, merge, or pick (got '$KIND'). If it is none of those, decide it yourself and record why on the work item." ;;
esac

for pair in "WHAT:$WHAT" "WHAT YOU DO (--you-do):$YOU_DO" "WHY BLOCKED (--why-blocked):$WHY" "ARTIFACT:$ARTIFACT" "STAKES:$STAKES"; do
    name=${pair%%:*}
    value=${pair#*:}
    if blank "$value"; then
        die "$name is required; a decision with a missing field is not filed"
    fi
done

[ -n "$KEY" ] || die "--key is required; every decision needs a stable key"

# ARTIFACT must be something the captain can open, not a bare number.
if printf '%s' "$ARTIFACT" | grep -Eq '^[[:space:]]*#?[0-9]+[[:space:]]*$'; then
    die "ARTIFACT must be a full URL or path, not a bare number ('$ARTIFACT')"
fi

case "$KEY" in
    *[!A-Za-z0-9._-]*) die "--key may contain only letters, digits, '.', '_' and '-'" ;;
esac

case "$BINDING" in
    ""|[!A-Za-z]*|*[!A-Za-z0-9_-]*) die "--binding must be a non-empty plain identifier" ;;
esac

for pair in "WHAT:$WHAT" "WHAT YOU DO (--you-do):$YOU_DO" "WHY BLOCKED (--why-blocked):$WHY" "ARTIFACT:$ARTIFACT" "STAKES:$STAKES"; do
    name=${pair%%:*}
    value=${pair#*:}
    if bare_pr_reference "$value" || pr_url_without_https "$value"; then
        die "$name must use a full https URL for every PR reference"
    fi
done

need_jq

existing=$(gcbd list --label "$LABEL" --label "decision-key:$KEY" --json --limit 0) \
    || die "could not read the ledger to check for key '$KEY'"
[ -n "$existing" ] || die "ledger read returned nothing (is the store reachable?)"
found=$(printf '%s' "$existing" | jq -r '.[0].id // empty') \
    || die "unexpected ledger payload while checking key '$KEY'"
if [ -n "$found" ]; then
    echo "EXISTING DECISION: $found (still open, key '$KEY'). Not filed again."
    exit 0
fi

first_line=$(printf '%s' "$WHAT" | head -n 1 | cut -c1-100)
title="[$KIND] $first_line"

body=$(printf 'WHAT: %s\nWHAT YOU DO: %s\nWHY BLOCKED: %s\nARTIFACT: %s\nSTAKES: %s\n\nFILED BY: %s\n' \
    "$WHAT" "$YOU_DO" "$WHY" "$ARTIFACT" "$STAKES" "$GC_AGENT")

labels="$LABEL,decision-kind:$KIND"
labels="$labels,decision-key:$KEY"

if [ -n "$BLOCKS" ]; then
    id=$(gcbd create "$title" --description "$body" --labels "$labels" \
        --deps "blocks:$BLOCKS" --silent) || die "could not file the decision"
else
    id=$(gcbd create "$title" --description "$body" --labels "$labels" \
        --silent) || die "could not file the decision"
fi

case "$id" in
    ""|*[[:space:]]*) die "filing returned an unexpected id ('$id'); run 'gc firstmate decide list' to check whether it landed" ;;
esac

cat <<EOF
DECISION FILED: $id (kind: $KIND)

Send this to the captain in plain words. Do not rewrite it into something else.

WHAT: $WHAT
WHAT YOU DO: $YOU_DO
WHY BLOCKED: $WHY
ARTIFACT: $ARTIFACT
STAKES: $STAKES

EOF
if [ "$KIND" = merge ]; then
    cat <<EOF
When they answer, record one of these exact outcomes:
  gc $BINDING resolve $id --answer "<their words>" --outcome approve
  gc $BINDING resolve $id --answer "<their words>" --outcome hold
EOF
else
    cat <<EOF
When they answer: gc $BINDING resolve $id --answer "<their words>"
EOF
fi
