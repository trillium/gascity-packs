#!/bin/sh
# shellcheck disable=SC2034  # CMD, GC and RIG are read by the sourced gate-lib.sh
# firstmate merge-gate - the scripted gate between "ready to land" and landing.
# Invoked as: gc firstmate merge-gate bind-captain|captain|check|land|revoke ...
#
# Environment (set by gc):
#   GC_BIN    - path to the gc binary (falls back to `gc` on PATH)
#   GC_AGENT  - the calling agent (required)
#   GC_RIG    - rig scope, when running from a rig agent (optional)
#   GC_PACK_DIR - this pack's directory (optional; located from $0 otherwise)
#   GH_BIN, GIT_BIN - optional overrides for gh / git (used by the tests)
#
# `check` is the live precondition script: it re-reads everything from the
# stores and from GitHub at the moment of the call and exits 0 only when every
# precondition holds. `land` runs `check` and then the landing command, so the
# refinery has no scripted path to a merge that skips the check.

set -eu

CMD="merge-gate"
GC="${GC_BIN:-gc}"
RIG="${GC_RIG:-}"

LIB="${GC_PACK_DIR:+$GC_PACK_DIR/assets/lib/gate-lib.sh}"
[ -f "${LIB:-}" ] || LIB="$(dirname -- "$0")/../../assets/lib/gate-lib.sh"
# shellcheck disable=SC1090
. "$LIB"

usage() {
    cat >&2 <<'USAGE'
usage:
  gc firstmate merge-gate bind-captain --id CAPTAIN_ID [--rig RIG]
  gc firstmate merge-gate captain [--rig RIG]
  gc firstmate merge-gate check WORK_BEAD_ID [--rig RIG]
  gc firstmate merge-gate land WORK_BEAD_ID [--rig RIG] -- LANDING_COMMAND [ARGS...]
  gc firstmate merge-gate revoke WORK_BEAD_ID --reason TEXT [--rig RIG]
USAGE
    exit 2
}

sub=${1:-}
[ -n "$sub" ] || usage
shift
case "$sub" in -h|--help|help) usage ;; esac
[ -n "${GC_AGENT:-}" ] || die "GC_AGENT is empty; refusing an unowned gate action"
need_jq

# ---- bind-captain ------------------------------------------------------------

do_bind() {
    id=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --id)  [ $# -ge 2 ] || usage; id=$2; shift 2 ;;
            --rig) [ $# -ge 2 ] || usage; RIG=$2; shift 2 ;;
            *) usage ;;
        esac
    done
    case "$id" in
        ""|*[!A-Za-z0-9._@-]*) die "--id must be a non-empty identity of letters, digits, '.', '_', '@' and '-'" ;;
    esac
    current=$(bound_captain)
    if [ -n "$current" ]; then
        die "a captain is already bound ('$current'); the binding is not changed from here. Close the $CAPTAIN_LABEL bead by hand to rebind."
    fi
    made=$(gcbd create "captain: $id" --description "The captain bound to this ledger. Only a merge decision resolved with --captain $id can authorize a landing. Bound by $GC_AGENT." \
        --labels "$CAPTAIN_LABEL,captain-id:$id" --silent) || die "could not bind the captain"
    case "$made" in
        ""|*[[:space:]]*) die "binding returned an unexpected id ('$made')" ;;
    esac
    echo "CAPTAIN BOUND: $id ($made)"
}

# ---- check -------------------------------------------------------------------

fail=0
refuse() {
    echo "REFUSED: $*"
    fail=1
}

# check_authority WORK - run every precondition; print one line per refusal.
# Returns 0 only when all pass.
check_authority() {
    work=$1
    fail=0

    captain=$(bound_captain)
    if [ -z "$captain" ]; then
        refuse "no captain is bound; run 'merge-gate bind-captain' first"
        return 1
    fi
    bead=$(work_bead "$work")
    status=$(printf '%s' "$bead" | jq -r '.status // empty')
    if [ "$status" = closed ]; then
        refuse "work bead $work is already closed"
        return 1
    fi

    flag=$(printf '%s' "$bead" | jq -r '.metadata.merge_authority // empty')
    dec=$(printf '%s' "$bead" | jq -r '.metadata.merge_authority_decision // empty')
    who=$(printf '%s' "$bead" | jq -r '.metadata.merge_authority_captain // empty')
    head=$(printf '%s' "$bead" | jq -r '.metadata.merge_authority_head // empty')
    case "$flag" in
        approved) ;;
        "") refuse "no merge authority on $work (no captain approval recorded)"; return 1 ;;
        *) refuse "merge authority on $work is '$flag', not 'approved'"; return 1 ;;
    esac
    if [ -z "$dec" ] || [ -z "$head" ]; then
        refuse "merge authority on $work lacks its decision or approved head"
        return 1
    fi
    [ "$who" = "$captain" ] || refuse "approval on $work names '$who', not the bound captain '$captain'"

    ledger=$(gcbd list --label firstmate-decision --all --json --limit 0) \
        || die "could not read the ledger"
    drow=$(printf '%s' "$ledger" | jq -c --arg id "$dec" '
        if type != "array" then error("unexpected ledger payload")
        else (map(select(.id == $id)) | .[0] // null) end') \
        || die "unexpected ledger payload"
    if [ "$drow" = null ]; then
        refuse "decision $dec is not in the ledger"
        return 1
    fi
    printf '%s' "$drow" | jq -e '.status == "closed"' >/dev/null \
        || refuse "decision $dec is not resolved"
    printf '%s' "$drow" | jq -e --arg w "decision-work:$work" '
        ((.labels // []) | index("decision-kind:merge") != null) and ((.labels // []) | index($w) != null)' >/dev/null \
        || refuse "decision $dec is not a merge decision for work bead $work"

    comments=$(gcbd comments "$dec" --json) || die "could not read the comments of decision $dec"
    text=$(printf '%s' "$comments" | jq -r '.. | strings') || die "unexpected comments payload"
    printf '%s\n' "$text" | grep -Fxq "OUTCOME: approve" \
        || refuse "decision $dec records no 'approve' outcome"
    if printf '%s\n' "$text" | grep -Fxq "OUTCOME: hold"; then
        refuse "decision $dec also records a 'hold' outcome"
    fi
    printf '%s\n' "$text" | grep -Fxq "CAPTAIN: $captain" \
        || refuse "decision $dec was not resolved as the bound captain '$captain'"
    printf '%s\n' "$text" | grep -Fxq "WORK: $work" \
        || refuse "decision $dec was not resolved for work bead $work"
    printf '%s\n' "$text" | grep -Fxq "HEAD: $head" \
        || refuse "decision $dec does not record the approved head $head"

    live=$(live_state "$bead")
    printf '%s' "$live" | jq -e '.open' >/dev/null || refuse "the change is no longer open"
    printf '%s' "$live" | jq -e '.ready' >/dev/null || refuse "the change is still a draft"
    printf '%s' "$live" | jq -e '.checks_ok' >/dev/null || refuse "the change has failing or pending checks"
    now=$(printf '%s' "$live" | jq -r '.head')
    [ "$now" = "$head" ] || refuse "the change moved since approval: approved $head, live $now"

    [ "$fail" -eq 0 ] || return 1
    echo "MERGE AUTHORIZED: $work (captain $captain, decision $dec, head $head)"
}

do_check() {
    work=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --rig) [ $# -ge 2 ] || usage; RIG=$2; shift 2 ;;
            -*) usage ;;
            *) [ -z "$work" ] || usage; work=$1; shift ;;
        esac
    done
    [ -n "$work" ] || usage
    check_authority "$work"
}

do_land() {
    work=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --rig) [ $# -ge 2 ] || usage; RIG=$2; shift 2 ;;
            --) shift; break ;;
            -*) usage ;;
            *) [ -z "$work" ] || usage; work=$1; shift ;;
        esac
    done
    [ -n "$work" ] && [ $# -gt 0 ] || usage
    check_authority "$work" || { echo "land: refused; nothing was run" >&2; exit 1; }
    gcbd comment "$work" "MERGE GATE: landing started by $GC_AGENT under captain approval." >/dev/null \
        || die "could not record the landing on $work; nothing was run"
    exec "$@"
}

do_revoke() {
    work=""; reason=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason) [ $# -ge 2 ] || usage; reason=$2; shift 2 ;;
            --rig)    [ $# -ge 2 ] || usage; RIG=$2; shift 2 ;;
            -*) usage ;;
            *) [ -z "$work" ] || usage; work=$1; shift ;;
        esac
    done
    [ -n "$work" ] || usage
    [ -n "$(printf '%s' "$reason" | tr -d '[:space:]')" ] || die "--reason is required"
    work_bead "$work" >/dev/null
    gcbd update "$work" --set-metadata merge_authority=revoked >/dev/null \
        || die "could not revoke authority on $work"
    gcbd comment "$work" "MERGE AUTHORITY REVOKED by $GC_AGENT: $reason" >/dev/null || true
    echo "MERGE AUTHORITY REVOKED: $work"
}

case "$sub" in
    bind-captain) do_bind "$@" ;;
    captain)
        while [ $# -gt 0 ]; do
            case "$1" in --rig) [ $# -ge 2 ] || usage; RIG=$2; shift 2 ;; *) usage ;; esac
        done
        c=$(bound_captain)
        if [ -n "$c" ]; then echo "$c"; else echo "no captain bound"; exit 1; fi
        ;;
    check)  do_check "$@" ;;
    land)   do_land "$@" ;;
    revoke) do_revoke "$@" ;;
    *) echo "merge-gate: unknown subcommand: $sub" >&2; usage ;;
esac
