# firstmate resolve

Record the captain's answer to a filed decision and close it.

```text
gc firstmate resolve ID --answer "what the captain said" [--outcome OUTCOME] [--captain CAPTAIN_ID] [--rig RIG]
```

`ID` is the exact id printed by `gc firstmate decide`. The command looks the id
up among beads labeled `firstmate-decision`, so it refuses ids that are not
decisions and ids that are already resolved (`gc bd` itself fuzzy-matches bare
ids; this command does not).

`--answer` is required and must be the captain's own words, verbatim. It is
written to the decision as a comment first, then the decision is closed. If the
close fails, the answer is still on file and the decision stays open.

For a `merge` decision, `--outcome` and `--captain` are required. Use either
`--outcome approve` or `--outcome hold`. `--captain` must be the id bound with
`gc firstmate merge-gate bind-captain`; any other value is refused, as is a
resolve before a captain is bound. The decision names its work bead (it was
filed with `--blocks`). `approve` reads the PR's live head, records
`CAPTAIN`, `WORK` and `HEAD` in the comment, and sets the work bead's
`merge_authority` flag to `approved`; `hold` sets it to `held`. The refinery
can land only through `gc firstmate merge-gate land`, which re-checks it all.
Other decision kinds do not accept `--outcome` or `--captain`.

A decision with no recorded answer is still open, whatever was said in chat.
Record the answer before acting on it.

Environment variables set by gc:
  GC_BIN         Path to the gc binary
  GC_AGENT       Calling agent (required)
  GC_RIG         Rig scope, when set
