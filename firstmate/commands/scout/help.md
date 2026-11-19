# firstmate scout

Launch a read-only investigation that ends in a report. Nothing is done until
the report passes the completion gate.

```text
gc firstmate scout launch --question TEXT --key KEY --report ABS_PATH \
    [--binding BINDING] [--rig RIG]
gc firstmate scout report ID --file ABS_PATH [--rig RIG]
gc firstmate scout check ID [--rig RIG]
gc firstmate scout done ID [--rig RIG]
gc firstmate scout list [--all] [--rig RIG]
```

| Subcommand | Who | What it does |
|------------|-----|--------------|
| `launch` | Mayor | Files a bead labeled `firstmate-scout`, `scout-key:<key>`; its description holds QUESTION and REPORT (the absolute report path). Prints the formula launch line. Idempotent on `--key`. |
| `report` | Scout | Checks the file exists, is not blank, and has the sections `## Question`, `## Findings`, `## Evidence`, `## Not verified`; then labels the bead `scout-report-submitted`. |
| `check` | Mayor | The completion gate: passes only if the report was submitted **and** the file at REPORT still exists with every section. Read-only. |
| `done` | Mayor | Runs the gate, then closes the bead with the report path as the reason. Refuses if the gate fails. |
| `list` | Anyone | Lists scouts. |

The Mayor relays a scout's result to the captain only after `check` or `done`
prints `SCOUT GATE PASSED`. A status line or a bead state is not the report.

The scout formula is `scout` (`formulas/scout.toml`). Read-only is a rule in
its steps, not an enforced sandbox.
