# firstmate resolve

Record the captain's answer to a filed decision and close it.

```text
gc firstmate resolve ID --answer "what the captain said" [--outcome OUTCOME] [--rig RIG]
```

`ID` is the exact id printed by `gc firstmate decide`. The command looks the id
up among beads labeled `firstmate-decision`, so it refuses ids that are not
decisions and ids that are already resolved (`gc bd` itself fuzzy-matches bare
ids; this command does not).

`--answer` is required and must be the captain's own words, verbatim. It is
written to the decision as a comment first, then the decision is closed. If the
close fails, the answer is still on file and the decision stays open.

For a `merge` decision, `--outcome` is required and recorded with the answer.
Use either `--outcome approve` or `--outcome hold`. Only `approve` authorizes
the refinery to land that exact change; `hold` keeps it unlanded. Other
decision kinds do not accept `--outcome`.

A decision with no recorded answer is still open, whatever was said in chat.
Record the answer before acting on it.

Environment variables set by gc:
  GC_BIN         Path to the gc binary
  GC_AGENT       Calling agent (required)
  GC_RIG         Rig scope, when set
