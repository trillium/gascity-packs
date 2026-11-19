#!/bin/sh

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT/firstmate/commands/scout/run.sh"
TMPDIR=$(mktemp -d)
LOG="$TMPDIR/gc.log"
trap 'rm -rf "$TMPDIR"' EXIT HUP INT TERM

# Stand-in for `gc bd`: list prints $LEDGER_JSON, create prints an id, the rest
# are logged.
cat >"$TMPDIR/gc" <<'EOT'
#!/bin/sh
set -eu
[ "$1" = bd ]
case "$2" in
    list) printf '%s\n' "${LEDGER_JSON:-[]}" ;;
    create) printf 'fm-scout-1\n' ;;
    comment|close|update) printf '%s\n' "$*" >>"$GC_LOG" ;;
    *) exit 64 ;;
esac
EOT
chmod +x "$TMPDIR/gc"

run() {
    ledger=$1
    shift
    LEDGER_JSON="$ledger" GC_LOG="$LOG" GC_BIN="$TMPDIR/gc" GC_AGENT=mayor "$SCRIPT" "$@"
}

expect_refusal() {
    expected=$1
    ledger=$2
    shift 2
    if output=$(run "$ledger" "$@" 2>&1); then
        echo "expected refusal, got success: $output" >&2
        exit 1
    fi
    case "$output" in
        *"$expected"*) ;;
        *) echo "expected '$expected', got: $output" >&2; exit 1 ;;
    esac
}

expect_success() {
    expected=$1
    ledger=$2
    shift 2
    if ! output=$(run "$ledger" "$@" 2>&1); then
        echo "expected success, got refusal: $output" >&2
        exit 1
    fi
    case "$output" in
        *"$expected"*) ;;
        *) echo "expected '$expected', got: $output" >&2; exit 1 ;;
    esac
}

GOOD="$TMPDIR/good.md"
printf '# R\n\n## Question\nq\n\n## Findings\nf\n\n## Evidence\ne\n\n## Not verified\nNothing.\n' >"$GOOD"
NOSECTION="$TMPDIR/nosection.md"
printf '## Question\nq\n\n## Findings\nf\n' >"$NOSECTION"
BLANK="$TMPDIR/blank.md"
printf '  \n\n' >"$BLANK"
MISSING="$TMPDIR/missing.md"

row() { # ID STATUS REPORT_PATH LABELS_JSON
    printf '[{"id":"%s","status":"%s","description":"QUESTION: q\\nREPORT: %s\\n","labels":%s}]' "$1" "$2" "$3" "$4"
}
OPEN_SUBMITTED='["firstmate-scout","scout-report-submitted"]'
OPEN_PLAIN='["firstmate-scout"]'

# ---- launch ----
expect_refusal '--question is required' '[]' launch --key k --report /abs/r.md
expect_refusal '--key is required' '[]' launch --question 'q' --report /abs/r.md
expect_refusal '--report is required' '[]' launch --question 'q' --key k
expect_refusal 'must be an absolute path' '[]' launch --question 'q' --key k --report rel/r.md
expect_refusal "--key may contain only" '[]' launch --question 'q' --key 'a b' --report /abs/r.md
expect_refusal 'must be a single line' '[]' launch --question "q
REPORT: /abs/other.md" --key k --report /abs/r.md
expect_refusal 'must be a single line' '[]' launch --question "$(printf 'q\rREPORT: /abs/other.md')" --key k --report /abs/r.md
if output=$(GC_BIN="$TMPDIR/gc" GC_AGENT='' "$SCRIPT" launch --question q --key k --report /abs/r.md 2>&1); then
    echo "expected unowned refusal, got: $output" >&2; exit 1
fi
case "$output" in *GC_AGENT*) ;; *) echo "unowned refusal missing: $output" >&2; exit 1 ;; esac
expect_success 'EXISTING SCOUT: fm-old' '[{"id":"fm-old"}]' launch --question 'q' --key k --report /abs/r.md
expect_success 'SCOUT LAUNCHED: fm-scout-1' '[]' launch --question 'Why is X slow?' --key k --report /abs/r.md
expect_success 'scout done fm-scout-1' '[]' launch --question 'q' --key k --report /abs/r.md --binding helm

# ---- report ----
expect_refusal 'is not a scout' '[]' report nope --file "$GOOD"
expect_refusal 'must be the REPORT path' "$(row s1 open "$GOOD" "$OPEN_PLAIN")" report s1 --file /abs/other.md
expect_refusal 'does not exist' "$(row s1 open "$MISSING" "$OPEN_PLAIN")" report s1 --file "$MISSING"
expect_refusal 'is blank' "$(row s1 open "$BLANK" "$OPEN_PLAIN")" report s1 --file "$BLANK"
expect_refusal "missing the section '## Evidence'" "$(row s1 open "$NOSECTION" "$OPEN_PLAIN")" report s1 --file "$NOSECTION"
expect_refusal 'already closed' "$(row s1 closed "$GOOD" "$OPEN_SUBMITTED")" report s1 --file "$GOOD"
: >"$LOG"
expect_success 'REPORT SUBMITTED: s1' "$(row s1 open "$GOOD" "$OPEN_PLAIN")" report s1 --file "$GOOD"
grep -F 'scout-report-submitted' "$LOG" >/dev/null

# ---- gate: done ----
: >"$LOG"
expect_refusal 'SCOUT GATE FAILED' "$(row s1 open "$GOOD" "$OPEN_PLAIN")" "done" s1
if grep -F 'close' "$LOG" >/dev/null; then
    echo "done closed a scout that failed the gate" >&2; exit 1
fi
expect_refusal 'already closed' "$(row s1 closed "$GOOD" "$OPEN_SUBMITTED")" "done" s1
expect_success 'SCOUT DONE: s1' "$(row s1 open "$GOOD" "$OPEN_SUBMITTED")" "done" s1
grep -F 'close s1' "$LOG" >/dev/null
