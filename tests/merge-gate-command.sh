#!/bin/sh
# Static test for the merge gate: bind-captain, resolve, check, land, revoke,
# run end to end against the stateful stand-in gc and a stand-in gh.

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
GATE="$ROOT/firstmate/commands/merge-gate/run.sh"
DECIDE="$ROOT/firstmate/commands/decide/run.sh"
RESOLVE="$ROOT/firstmate/commands/resolve/run.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT HUP INT TERM
FAKE_DIR="$TMPDIR/store"
mkdir -p "$FAKE_DIR"
export FAKE_DIR

cp "$ROOT/tests/fake-gc.sh" "$TMPDIR/gc"
cat >"$TMPDIR/gh" <<'EOF'
#!/bin/sh
[ ! -f "$FAKE_DIR/gh-down" ] || exit 1
cat "$FAKE_DIR/pr.json"
EOF
chmod +x "$TMPDIR/gh"
export GC_BIN="$TMPDIR/gc" GH_BIN="$TMPDIR/gh" GC_AGENT=refinery

PR_URL=https://github.com/o/r/pull/12
HEAD1=1111111111111111111111111111111111111111
HEAD2=2222222222222222222222222222222222222222
DB="$FAKE_DIR/beads.json"

set_pr() { # head state draft check-conclusion
    printf '{"headRefOid":"%s","state":"%s","isDraft":%s,"statusCheckRollup":[{"conclusion":"%s"}]}\n' \
        "$1" "$2" "$3" "$4" >"$FAKE_DIR/pr.json"
}

# edit_db JQ_ARGS... - rewrite the stand-in store through a scratch file.
edit_db() {
    jq "$@" "$DB" >"$FAKE_DIR/edit.json"
    cp "$FAKE_DIR/edit.json" "$DB"
}

add_work() { # id metadata-json
    edit_db --arg id "$1" --argjson m "$2" \
        '. + [{id: $id, title: "work", status: "open", labels: [], metadata: $m, comments: []}]'
}

expect_fail() { # expected-substring cmd...
    expected=$1
    shift
    if out=$("$@" 2>&1); then
        echo "expected refusal containing '$expected', got success: $out" >&2
        exit 1
    fi
    case "$out" in
        *"$expected"*) ;;
        *) echo "expected '$expected', got: $out" >&2; exit 1 ;;
    esac
}

expect_ok() { # expected-substring cmd...
    expected=$1
    shift
    out=$("$@" 2>&1) || { echo "expected success, got: $out" >&2; exit 1; }
    case "$out" in
        *"$expected"*) ;;
        *) echo "expected '$expected', got: $out" >&2; exit 1 ;;
    esac
}

echo '[]' >"$DB"
set_pr "$HEAD1" OPEN false SUCCESS
add_work w-1 "{\"pr_url\": \"$PR_URL\"}"
add_work w-2 '{"pr_url": "https://github.com/o/r/pull/13"}'

file_merge() { # key work
    "$DECIDE" --kind merge --key "$1" --blocks "$2" --what 'Merge the login fix?' \
        --you-do 'Reply approve to let it land, or hold.' --why-blocked 'Only the captain merges.' \
        --artifact "$PR_URL" --stakes 'Login stays broken until merged; revertable.' >/dev/null
    jq -r --arg k "decision-key:$1" 'map(select(.labels | index($k))) | .[0].id' "$DB"
}

# A merge decision must name its work bead.
expect_fail '--blocks WORK_BEAD_ID is required' "$DECIDE" --kind merge --key nowork --what 'Merge it?' \
    --you-do 'Reply approve.' --why-blocked 'Only the captain merges.' --artifact "$PR_URL" --stakes 'Waits.'

D1=$(file_merge login-fix w-1)
jq -e --arg id "$D1" 'map(select(.id == $id)) | .[0].labels | index("decision-work:w-1") != null' "$DB" >/dev/null

# No captain bound: nothing can be approved or checked.
expect_fail 'no captain is bound' "$RESOLVE" "$D1" --answer 'approve' --outcome approve --captain trillium
expect_fail 'no captain is bound' "$GATE" check w-1
expect_fail 'no captain bound' "$GATE" captain

# Bind the captain once; the binding does not change from the gate.
expect_fail '--id must be' "$GATE" bind-captain --id 'bad id'
expect_ok 'CAPTAIN BOUND: trillium' "$GATE" bind-captain --id trillium
expect_fail 'already bound' "$GATE" bind-captain --id someone-else
expect_ok 'trillium' "$GATE" captain

# Resolve refusals for a merge decision.
expect_fail '--captain is required' "$RESOLVE" "$D1" --answer 'approve' --outcome approve
expect_fail 'is not the bound captain' "$RESOLVE" "$D1" --answer 'approve' --outcome approve --captain mallory
expect_fail '--outcome is required' "$RESOLVE" "$D1" --answer 'approve' --captain trillium

# Nothing approved yet: check and land both refuse, and land runs nothing.
expect_fail 'no merge authority on w-1' "$GATE" check w-1
: >"$TMPDIR/landed"
expect_fail 'nothing was run' "$GATE" land w-1 -- sh -c "echo ran >>'$TMPDIR/landed'"
[ ! -s "$TMPDIR/landed" ] || { echo "land ran without authority" >&2; exit 1; }

# Unreadable live state: approval is refused and the decision stays open.
: >"$FAKE_DIR/gh-down"
expect_fail 'could not read live PR state' "$RESOLVE" "$D1" --answer 'approve' --outcome approve --captain trillium
rm -f "$FAKE_DIR/gh-down"
jq -e --arg id "$D1" 'map(select(.id == $id)) | .[0].status == "open"' "$DB" >/dev/null

# Approve: flag, decision, captain and head are persisted.
expect_ok "w-1 may land at $HEAD1" "$RESOLVE" "$D1" --answer 'yes, approve it' --outcome approve --captain trillium
jq -e --arg d "$D1" --arg h "$HEAD1" 'map(select(.id == "w-1")) | .[0].metadata
    | .merge_authority == "approved" and .merge_authority_decision == $d
      and .merge_authority_captain == "trillium" and .merge_authority_head == $h' "$DB" >/dev/null
expect_ok "MERGE AUTHORIZED: w-1 (captain trillium, decision $D1, head $HEAD1)" "$GATE" check w-1

# Authority is per work bead: another bead pointing at this approval is refused.
edit_db --arg d "$D1" --arg h "$HEAD1" '(.[] | select(.id == "w-2") | .metadata) += {merge_authority: "approved", merge_authority_decision: $d, merge_authority_captain: "trillium", merge_authority_head: $h}'
expect_fail 'is not a merge decision for work bead w-2' "$GATE" check w-2
# A bare flag with no decision behind it is refused.
edit_db '(.[] | select(.id == "w-2") | .metadata.merge_authority_decision) = "nope"'
expect_fail 'decision nope is not in the ledger' "$GATE" check w-2

# Live preconditions are re-read on every call.
set_pr "$HEAD2" OPEN false SUCCESS
expect_fail 'moved since approval' "$GATE" check w-1
set_pr "$HEAD1" OPEN true SUCCESS
expect_fail 'still a draft' "$GATE" check w-1
set_pr "$HEAD1" OPEN false FAILURE
expect_fail 'failing or pending checks' "$GATE" check w-1
set_pr "$HEAD1" MERGED false SUCCESS
expect_fail 'no longer open' "$GATE" check w-1
: >"$FAKE_DIR/gh-down"
expect_fail 'could not read live PR state' "$GATE" check w-1
rm -f "$FAKE_DIR/gh-down"
set_pr "$HEAD1" OPEN false SUCCESS

# A tampered flag naming a different captain is refused.
edit_db '(.[] | select(.id == "w-1") | .metadata.merge_authority_captain) = "mallory"'
expect_fail "not the bound captain 'trillium'" "$GATE" check w-1
edit_db '(.[] | select(.id == "w-1") | .metadata.merge_authority_captain) = "trillium"'

# land runs the command only after the check passes.
expect_ok 'ran' "$GATE" land w-1 -- sh -c "echo ran | tee -a '$TMPDIR/landed'"
grep -Fx ran "$TMPDIR/landed" >/dev/null
jq -e 'map(select(.id == "w-1")) | .[0].comments | map(.text) | any(startswith("MERGE GATE: landing started"))' "$DB" >/dev/null

# Revoke withdraws authority.
expect_fail '--reason is required' "$GATE" revoke w-1 --reason ''
expect_ok 'MERGE AUTHORITY REVOKED: w-1' "$GATE" revoke w-1 --reason 'captain changed their mind'
expect_fail "is 'revoked', not 'approved'" "$GATE" check w-1

# A hold never authorizes landing.
add_work w-3 '{"pr_url": "https://github.com/o/r/pull/14"}'
D3=$(file_merge search-fix w-3)
expect_ok 'Hold recorded' "$RESOLVE" "$D3" --answer 'not yet' --outcome hold --captain trillium
jq -e 'map(select(.id == "w-3")) | .[0].metadata.merge_authority == "held"' "$DB" >/dev/null
expect_fail "is 'held', not 'approved'" "$GATE" check w-3

# An approval for a work bead that is already closed is refused.
add_work w-4 '{"pr_url": "https://github.com/o/r/pull/15"}'
D4=$(file_merge closed-work w-4)
edit_db '(.[] | select(.id == "w-4") | .status) = "closed"'
expect_fail 'already closed' "$RESOLVE" "$D4" --answer 'approve' --outcome approve --captain trillium

# Branch-only work (no PR): live head comes from git ls-remote.
cat >"$TMPDIR/git" <<'EOF'
#!/bin/sh
printf '%s\trefs/heads/%s\n' "$(cat "$FAKE_DIR/branch-head")" "${3#refs/heads/}"
EOF
chmod +x "$TMPDIR/git"
export GIT_BIN="$TMPDIR/git"
printf '%s' "$HEAD1" >"$FAKE_DIR/branch-head"
add_work w-5 '{"branch": "polecat/x"}'
D5=$(file_merge branch-work w-5)
expect_ok "w-5 may land at $HEAD1" "$RESOLVE" "$D5" --answer 'approve' --outcome approve --captain trillium
expect_ok 'MERGE AUTHORIZED: w-5' "$GATE" check w-5
printf '%s' "$HEAD2" >"$FAKE_DIR/branch-head"
expect_fail 'moved since approval' "$GATE" check w-5

echo "merge-gate tests passed"
