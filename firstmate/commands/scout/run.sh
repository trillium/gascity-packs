#!/bin/sh
# firstmate scout - launch a read-only scout, take its report, gate completion.
# Invoked as: gc firstmate scout launch|report|check|done|list ...
#
# Environment (set by gc):
#   GC_BIN    - path to the gc binary (falls back to `gc` on PATH)
#   GC_AGENT  - the calling agent (required for launch/report/done)
#   GC_RIG    - rig scope, when running from a rig agent (optional)
#
# A scout is a bead labeled `firstmate-scout` whose description holds QUESTION
# and REPORT (an absolute path). The scout writes only that file, then runs
# `report`. `check` / `done` are the completion gate: they re-read the file, so
# a stale label alone never passes.

set -eu

LABEL="firstmate-scout"
SUBMITTED="scout-report-submitted"
GC="${GC_BIN:-gc}"
RIG="${GC_RIG:-}"
BINDING="firstmate"
SECTIONS="## Question|## Findings|## Evidence|## Not verified"

usage() {
    cat >&2 <<'EOT'
usage:
  gc firstmate scout launch --question TEXT --key KEY --report ABS_PATH \
      [--binding BINDING] [--rig RIG]
  gc firstmate scout report ID --file ABS_PATH [--rig RIG]
  gc firstmate scout check ID [--rig RIG]
  gc firstmate scout done ID [--rig RIG]
  gc firstmate scout list [--all] [--rig RIG]
EOT
    exit 2
}

die() {
    echo "scout: $*" >&2
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

need_value() {
    [ "$2" -ge 2 ] || { echo "scout: $1 needs a value" >&2; usage; }
}

blank() {
    [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]
}

need_agent() {
    [ -n "${GC_AGENT:-}" ] || die "GC_AGENT is empty; refusing an unowned transition"
}

# check_report_file PATH - succeed only for an absolute, non-blank report that
# has every required section. Prints the reason on failure.
check_report_file() {
    path=$1
    case "$path" in
        /*) ;;
        *) echo "report path must be absolute ('$path')"; return 1 ;;
    esac
    [ -f "$path" ] || { echo "report file does not exist: $path"; return 1; }
    if blank "$(cat "$path")"; then
        echo "report file is blank: $path"
        return 1
    fi
    oldifs=$IFS
    IFS='|'
    for heading in $SECTIONS; do
        if ! grep -Fxq "$heading" "$path"; then
            IFS=$oldifs
            echo "report is missing the section '$heading': $path"
            return 1
        fi
    done
    IFS=$oldifs
    return 0
}

# load_scout ID - set SCOUT_STATUS, SCOUT_REPORT, SCOUT_SUBMITTED from the
# ledger. Matches the id exactly: gc bd fuzzy-matches bare ids.
load_scout() {
    id=$1
    need_jq
    listing=$(gcbd list --label "$LABEL" --all --json --limit 0) \
        || die "could not read the scout ledger"
    [ -n "$listing" ] || die "scout ledger read returned nothing (is the store reachable?)"
    row=$(printf '%s' "$listing" | jq -c --arg id "$id" '
        if type != "array" then error("unexpected ledger payload")
        else (map(select(.id == $id)) | .[0] // null) end') \
        || die "unexpected ledger payload"
    SCOUT_STATUS=$(printf '%s' "$row" | jq -r '.status // empty') \
        || die "unexpected scout payload"
    [ -n "$SCOUT_STATUS" ] || die "'$id' is not a scout (exact id required); run 'gc firstmate scout list'"
    SCOUT_REPORT=$(printf '%s' "$row" | jq -r '(.description // "") | split("\n") | map(select(startswith("REPORT: "))) | .[0] // "" | sub("^REPORT: "; "")') \
        || die "unexpected scout payload"
    SCOUT_SUBMITTED=$(printf '%s' "$row" | jq -r --arg l "$SUBMITTED" '
        (.labels // []) as $labels |
        if ($labels | type) == "array" then ($labels | index($l) != null)
        else ($labels | tostring | contains($l)) end') \
        || die "unexpected scout labels"
}

# gate ID - the completion gate. Prints the verdict; returns 0 only on pass.
gate() {
    load_scout "$1"
    [ -n "$SCOUT_REPORT" ] || { echo "SCOUT GATE FAILED: $1 has no REPORT path recorded"; return 1; }
    if [ "$SCOUT_SUBMITTED" != true ]; then
        echo "SCOUT GATE FAILED: $1 has no submitted report; the scout must run 'gc $BINDING scout report $1 --file $SCOUT_REPORT'"
        return 1
    fi
    if ! reason=$(check_report_file "$SCOUT_REPORT"); then
        echo "SCOUT GATE FAILED: $reason"
        return 1
    fi
    echo "SCOUT GATE PASSED: $1"
    echo "Report: $SCOUT_REPORT"
    return 0
}

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
    out=$(gcbd list --label "$LABEL" $all --json --limit 0) || die "could not read the scout ledger"
    [ -n "$out" ] || die "scout ledger read returned nothing (is the store reachable?)"
    printf '%s' "$out" | jq -r '
        if (type != "array") then error("unexpected ledger payload")
        elif length == 0 then "no scouts"
        else sort_by(.created_at // "") | .[] | "\(.id)\t\(.status)\t\(.title)"
        end'
}

do_launch() {
    QUESTION=""; KEY=""; REPORT=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --question) need_value "$1" "$#"; QUESTION=$2; shift 2 ;;
            --key)      need_value "$1" "$#"; KEY=$2; shift 2 ;;
            --report)   need_value "$1" "$#"; REPORT=$2; shift 2 ;;
            --binding)  need_value "$1" "$#"; BINDING=$2; shift 2 ;;
            --rig)      need_value "$1" "$#"; RIG=$2; shift 2 ;;
            *) echo "scout: unknown argument: $1" >&2; usage ;;
        esac
    done
    need_agent
    blank "$QUESTION" && die "--question is required"
    [ -n "$KEY" ] || die "--key is required; every scout needs a stable key"
    case "$KEY" in
        *[!A-Za-z0-9._-]*) die "--key may contain only letters, digits, '.', '_' and '-'" ;;
    esac
    case "$REPORT" in
        /*) ;;
        "") die "--report is required: the absolute path the report will be written to" ;;
        *) die "--report must be an absolute path ('$REPORT')" ;;
    esac
    case "$REPORT" in
        *[[:space:]]*) die "--report must not contain whitespace" ;;
    esac
    case "$BINDING" in
        ""|[!A-Za-z]*|*[!A-Za-z0-9_-]*) die "--binding must be a non-empty plain identifier" ;;
    esac
    need_jq

    existing=$(gcbd list --label "$LABEL" --label "scout-key:$KEY" --all --json --limit 0) \
        || die "could not read the scout ledger to check for key '$KEY'"
    [ -n "$existing" ] || die "scout ledger read returned nothing (is the store reachable?)"
    found=$(printf '%s' "$existing" | jq -r '.[0].id // empty') \
        || die "unexpected ledger payload while checking key '$KEY'"
    if [ -n "$found" ]; then
        echo "EXISTING SCOUT: $found (key '$KEY'). Not launched again."
        exit 0
    fi

    title="[scout] $(printf '%s' "$QUESTION" | head -n 1 | cut -c1-100)"
    body=$(printf 'QUESTION: %s\nREPORT: %s\n\nLAUNCHED BY: %s\nREAD-ONLY: the scout writes only the REPORT file.\n' \
        "$QUESTION" "$REPORT" "$GC_AGENT")
    id=$(gcbd create "$title" --description "$body" \
        --labels "$LABEL,scout-key:$KEY" --silent) || die "could not file the scout"
    case "$id" in
        ""|*[[:space:]]*) die "filing returned an unexpected id ('$id'); run 'gc $BINDING scout list' to check whether it landed" ;;
    esac

    cat <<EOT
SCOUT LAUNCHED: $id (key: $KEY)

Report will be written to: $REPORT

Next: hand the bead to a worker with the scout formula, for example
  gc sling <rig>/<polecat> $id --formula scout --var bead=$id --var question="<question>" --var report=$REPORT --var binding=$BINDING
Do not tell the captain anything about the result yet. After the scout submits:
  gc $BINDING scout done $id
Relay the result only after it prints SCOUT GATE PASSED.
EOT
}

do_report() {
    ID=""; FILE=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --file) need_value "$1" "$#"; FILE=$2; shift 2 ;;
            --rig)  need_value "$1" "$#"; RIG=$2; shift 2 ;;
            -*) echo "scout: unknown argument: $1" >&2; usage ;;
            *) [ -z "$ID" ] || usage; ID=$1; shift ;;
        esac
    done
    [ -n "$ID" ] || usage
    [ -n "$FILE" ] || die "--file is required"
    need_agent
    load_scout "$ID"
    [ "$SCOUT_STATUS" != closed ] || die "'$ID' is already closed"
    [ "$FILE" = "$SCOUT_REPORT" ] || die "--file must be the REPORT path recorded on '$ID': $SCOUT_REPORT"
    if ! reason=$(check_report_file "$FILE"); then
        die "$reason"
    fi
    gcbd comment "$ID" "REPORT SUBMITTED by $GC_AGENT: $FILE" \
        || die "could not record the report on '$ID'"
    gcbd update "$ID" --add-label "$SUBMITTED" \
        || die "could not label '$ID' $SUBMITTED"
    echo "REPORT SUBMITTED: $ID"
    echo "Report: $FILE"
    echo "The Mayor closes this scout with: gc $BINDING scout done $ID"
}

do_check() {
    [ $# -eq 1 ] || { [ $# -eq 3 ] && [ "$2" = --rig ]; } || usage
    ID=$1
    [ $# -eq 3 ] && RIG=$3
    gate "$ID"
}

do_done() {
    [ $# -eq 1 ] || { [ $# -eq 3 ] && [ "$2" = --rig ]; } || usage
    ID=$1
    [ $# -eq 3 ] && RIG=$3
    need_agent
    load_scout "$ID"
    [ "$SCOUT_STATUS" != closed ] || die "'$ID' is already closed"
    if ! verdict=$(gate "$ID"); then
        echo "$verdict" >&2
        exit 1
    fi
    if ! gcbd close "$ID" --reason "scout report passed the gate: $SCOUT_REPORT"; then
        die "gate passed but closing '$ID' failed; retry: gc bd close $ID"
    fi
    echo "$verdict"
    echo "SCOUT DONE: $ID closed. Relay the report to the captain (outcome first)."
}

case "${1:-}" in
    launch) shift; do_launch "$@" ;;
    report) shift; do_report "$@" ;;
    check)  shift; do_check "$@" ;;
    done)   shift; do_done "$@" ;;
    list)   shift; do_list "$@" ;;
    *) usage ;;
esac
