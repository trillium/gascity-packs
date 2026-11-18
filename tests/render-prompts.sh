#!/bin/sh

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
PIN=0f07496d2fa4fd957a8bea77dcfd653c5d4bcef5
BASE="https://raw.githubusercontent.com/gastownhall/gascity-packs/$PIN/gastown/template-fragments"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT HUP INT TERM

for fragment in approval-fallacy architecture capability-ledger command-glossary following-mol operational-awareness propulsion tdd-discipline; do
    curl -fsSL "$BASE/$fragment.template.md" >"$TMPDIR/$fragment.template.md"
done

go run "$ROOT/tests/render-prompts.go" "$ROOT" "$TMPDIR"
