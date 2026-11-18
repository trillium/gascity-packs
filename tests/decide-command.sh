#!/bin/sh

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT/firstmate/commands/decide/run.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT HUP INT TERM

cat >"$TMPDIR/gc" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = bd ]
case "$2" in
    list) printf '%s\n' "${DECIDE_LEDGER_JSON:-[]}" ;;
    create) printf 'fm-decision-1\n' ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$TMPDIR/gc"

run() {
    GC_BIN="$TMPDIR/gc" GC_AGENT=mayor "$SCRIPT" "$@"
}

run_with_ledger() {
    ledger=$1
    shift
    DECIDE_LEDGER_JSON="$ledger" GC_BIN="$TMPDIR/gc" GC_AGENT=mayor "$SCRIPT" "$@"
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

expect_filed() {
    if output=$(run "$@" 2>&1); then
        case "$output" in
            *'DECISION FILED: fm-decision-1'*) ;;
            *) echo "expected filed decision, got: $output" >&2; exit 1 ;;
        esac
    else
        echo "expected filing, got refusal: $output" >&2
        exit 1
    fi
}

expect_unowned_refusal() {
    if output=$(GC_BIN="$TMPDIR/gc" GC_AGENT='' "$SCRIPT" "$@" 2>&1); then
        echo "expected refusal, got success: $output" >&2
        exit 1
    fi
    case "$output" in
        *'GC_AGENT is empty'*) ;;
        *) echo "expected unowned refusal, got: $output" >&2; exit 1 ;;
    esac
}

expect_refusal '--key is required' \
    --kind merge --what 'Merge the login fix?' --you-do 'Open the linked change.' \
    --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' \
    --stakes 'The fix remains unavailable.'

expect_unowned_refusal \
    --kind merge --key merge-login-fix --what 'Merge the login fix?' \
    --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' \
    --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.'

expect_refusal 'STAKES is required' \
    --kind merge --key merge-login-fix --what 'Merge the login fix?' \
    --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' \
    --artifact 'https://github.com/org/repo/pull/12' --stakes ''

expect_refusal 'must end with a question mark' \
    --kind merge --key merge-login-fix --what 'Merge the login fix' \
    --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' \
    --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.'

expect_refusal '--kind must be approve, merge, or pick' \
    --kind defer --key merge-login-fix --what 'Merge the login fix?' \
    --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' \
    --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.'

expect_refusal 'ARTIFACT must be a full URL or path' \
    --kind merge --key merge-login-fix --what 'Merge the login fix?' \
    --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' \
    --artifact '#12' --stakes 'The fix remains unavailable.'

expect_refusal '--binding must be a non-empty plain identifier' \
    --kind merge --key merge-login-fix --binding 'bad;binding' --what 'Merge the login fix?' \
    --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' \
    --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.'

expect_refusal 'full https URL' \
    --kind merge --key merge-login-fix --what 'Merge the login fix?' \
    --you-do 'Open the PR and merge it.' --why-blocked 'Only the captain merges.' \
    --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.'

for field in what you-do why-blocked artifact stakes; do
    case "$field" in
        what) set -- --kind merge --key merge-login-fix --what 'Pull request #12?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        you-do) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open PR #12.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        why-blocked) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Pull request #12 needs the captain.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        artifact) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'Pull request #12' --stakes 'The fix remains unavailable.' ;;
        stakes) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'Pull request #12 remains unavailable.' ;;
    esac
    expect_refusal 'full https URL' "$@"
done

for field in what you-do why-blocked artifact stakes; do
    case "$field" in
        what) set -- --kind merge --key merge-login-fix --what 'Review PR: 13 and https://github.com/org/repo/pull/12?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        you-do) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Review PR: 13 and https://github.com/org/repo/pull/12.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        why-blocked) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Review PR: 13 and https://github.com/org/repo/pull/12.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        artifact) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'Review PR: 13 and https://github.com/org/repo/pull/12.' --stakes 'The fix remains unavailable.' ;;
        stakes) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'Review PR: 13 and https://github.com/org/repo/pull/12 remains unavailable.' ;;
    esac
    expect_refusal 'full https URL' "$@"
done

for field in what you-do why-blocked artifact stakes; do
    case "$field" in
        what) set -- --kind merge --key merge-login-fix --what 'Review https://docs.example.com/runbook/#12?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        you-do) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Review https://docs.example.com/runbook/#12.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        why-blocked) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Review https://docs.example.com/runbook/#12.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        artifact) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://docs.example.com/runbook/#12' --stakes 'The fix remains unavailable.' ;;
        stakes) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'Review https://docs.example.com/runbook/#12 remains unavailable.' ;;
    esac
    expect_filed "$@"
done

# A PR label directly followed by a full https URL is a valid reference.
for field in what you-do why-blocked artifact stakes; do
    case "$field" in
        what) set -- --kind merge --key merge-login-fix --what 'Merge PR: https://github.com/org/repo/pull/12?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        you-do) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open PR https://github.com/org/repo/pull/12.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        why-blocked) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Pull request: https://github.com/org/repo/pull/12 is waiting.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        artifact) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'PR: https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        stakes) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'PR https://github.com/org/repo/pull/12 stays unmerged.' ;;
    esac
    expect_filed "$@"
done

# A bare PR reference is still refused even with a valid https artifact elsewhere.
for field in what you-do why-blocked artifact stakes; do
    case "$field" in
        what) set -- --kind merge --key merge-login-fix --what 'Merge PR 13?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        you-do) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open PR 13.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        why-blocked) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Pull request 13 is waiting.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        artifact) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'PR 13' --stakes 'The fix remains unavailable.' ;;
        stakes) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'PR 13 stays unmerged.' ;;
    esac
    expect_refusal 'full https URL' "$@"
done

for field in what you-do why-blocked artifact stakes; do
    case "$field" in
        what) set -- --kind merge --key merge-login-fix --what 'Merge trillium/gascity-packs#12?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        you-do) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open trillium/gascity-packs#12.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        why-blocked) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'trillium/gascity-packs#12 needs the captain.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        artifact) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'trillium/gascity-packs#12' --stakes 'The fix remains unavailable.' ;;
        stakes) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'trillium/gascity-packs#12 remains unavailable.' ;;
    esac
    expect_refusal 'full https URL' "$@"
done

for field in what you-do why-blocked artifact stakes; do
    case "$field" in
        what) set -- --kind merge --key merge-login-fix --what 'Review http://github.com/org/repo/pull/12?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        you-do) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open http://github.com/org/repo/pull/12.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        why-blocked) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'http://github.com/org/repo/pull/12 needs the captain.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        artifact) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'http://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        stakes) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'http://github.com/org/repo/pull/12 remains unavailable.' ;;
    esac
    expect_refusal 'full https URL' "$@"
done

output=$(run --kind merge --key merge-login-fix --binding helm --what 'Merge the login fix?' \
    --you-do 'Open the linked change and merge it.' --why-blocked 'Only the captain merges.' \
    --artifact 'https://github.com/org/repo/pull/12' \
    --stakes 'The fix remains unavailable until the captain merges it.')
case "$output" in
    *'DECISION FILED: fm-decision-1 (kind: merge)'*'Only the captain merges.'*'gc helm resolve fm-decision-1'*) ;;
    *) echo "accepted merge was not filed as a captain decision: $output" >&2; exit 1 ;;
esac

output=$(run --kind approve --key approve-copy --what 'Approve the release copy?' \
    --you-do 'Reply yes or no.' --why-blocked 'Only the captain chooses release wording.' \
    --artifact 'https://docs.example.com/runbook#12' --stakes 'The release waits for copy approval.')
case "$output" in
    *'gc firstmate resolve fm-decision-1 --answer "<their words>"'*'--outcome'*) echo "non-merge hint included outcome syntax: $output" >&2; exit 1 ;;
    *'gc firstmate resolve fm-decision-1 --answer "<their words>"'*) ;;
    *) echo "default binding hint was not printed: $output" >&2; exit 1 ;;
esac

duplicate='[{"id":"d-existing","status":"open","labels":["firstmate-decision","decision-key:merge-login-fix"]}]'
output=$(run_with_ledger "$duplicate" --kind merge --key merge-login-fix --what 'Merge the login fix?' \
    --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' \
    --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.')
case "$output" in
    *'EXISTING DECISION: d-existing'*) ;;
    *) echo "duplicate key was not returned: $output" >&2; exit 1 ;;
esac

"$ROOT/tests/resolve-command.sh"
"$ROOT/tests/render-prompts.sh"
