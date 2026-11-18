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
    list) printf '[]\n' ;;
    create) printf 'fm-decision-1\n' ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$TMPDIR/gc"

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

expect_refusal '--key is required' \
    --kind merge --what 'Merge the login fix?' --you-do 'Open the linked change.' \
    --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' \
    --stakes 'The fix remains unavailable.'

expect_refusal 'must end with a question mark' \
    --kind merge --key merge-login-fix --what 'Merge the login fix' \
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
        what) set -- --kind merge --key merge-login-fix --what 'Merge trillium/gascity-packs#12?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        you-do) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open trillium/gascity-packs#12.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        why-blocked) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'trillium/gascity-packs#12 needs the captain.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'The fix remains unavailable.' ;;
        artifact) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'trillium/gascity-packs#12' --stakes 'The fix remains unavailable.' ;;
        stakes) set -- --kind merge --key merge-login-fix --what 'Merge the login fix?' --you-do 'Open the linked change.' --why-blocked 'Only the captain merges.' --artifact 'https://github.com/org/repo/pull/12' --stakes 'trillium/gascity-packs#12 remains unavailable.' ;;
    esac
    expect_refusal 'full https URL' "$@"
done

output=$(GC_PACK_NAME=helm GC_BIN="$TMPDIR/gc" GC_AGENT=mayor "$SCRIPT" --kind merge --key merge-login-fix --what 'Merge the login fix?' \
    --you-do 'Open the linked change and merge it.' --why-blocked 'Only the captain merges.' \
    --artifact 'https://github.com/org/repo/pull/12' \
    --stakes 'The fix remains unavailable until the captain merges it.')
case "$output" in
    *'DECISION FILED: fm-decision-1 (kind: merge)'*'Only the captain merges.'*'gc helm resolve fm-decision-1'*) ;;
    *) echo "accepted merge was not filed as a captain decision: $output" >&2; exit 1 ;;
esac

"$ROOT/tests/resolve-command.sh"
"$ROOT/tests/render-prompts.sh"
