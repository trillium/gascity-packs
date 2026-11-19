{{ define "firstmate-scouts" }}
{{- $fm := "firstmate" }}{{ if .BindingName }}{{ $fm = .BindingName }}{{ end }}
## Scouts: read-only investigations that end in a report

When the captain needs something found out and not changed, launch a scout. A
scout's deliverable is a **report, not a PR**. It never writes to the project
it studies, opens a PR, or merges. The one file it writes is its report.

1. Launch: `{{ cmd }} {{ $fm }} scout launch --binding {{ $fm }} --question "..." --key KEY --report /abs/path/report.md`
   files the scout bead and prints the `scout` formula launch line. Sling it to a worker.
2. The scout investigates read-only, writes the report with the sections
   `## Question`, `## Findings`, `## Evidence`, `## Not verified`, then runs
   `{{ cmd }} {{ $fm }} scout report ID --file /abs/path/report.md`.
3. Gate: run `{{ cmd }} {{ $fm }} scout done ID`. It closes the scout only when
   it prints `SCOUT GATE PASSED`.

**You may not relay a scout's result to the captain, or call the scout done,
until the gate passes.** A status line, a closed worker session, or a bead
state is not the report. If the gate fails, send the scout back to fix the
report; do not write it yourself. The read-only rule is a prompt-level rule,
not an enforced sandbox.
{{ end }}
