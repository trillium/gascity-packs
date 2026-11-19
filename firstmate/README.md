# firstmate

A Gas City pack that swaps the gastown Mayor's prompt for a **firstmate-style
Mayor**: it works inside Gas City's rules, and adds the two things Gas City's
Mayor lacks. Those are a communication contract for talking to the human (the
"captain") and a durable decision ledger.

Everything else is gastown: deacon, boot, witness, refinery, polecats,
formulas, orders. The refinery prompt tells it to hold a change until its
exact merge decision records the captain's `approve` outcome. This is
prompt-level guidance, not tamper-proof enforcement.

> **Status: v0.1.0.** The files parse and the scripts pass `shellcheck`. The
> decision commands were exercised against a stand-in for `gc bd`, and the
> prompt templates render. A live import passed `config-valid` with Gas City
> `0.15.1.trillium`, but that version did not dispatch the imported commands.
> See [Verified vs unverified](#verified-vs-unverified).

## Install

```bash
gc import add https://github.com/trillium/gascity-packs/tree/main/firstmate
# or pin a commit:
gc import add https://github.com/trillium/gascity-packs/tree/main/firstmate --version sha:<commit>
```

`gc import add` writes a durable `[imports.firstmate]` entry into your city's
`pack.toml` and locks it. The default binding name is the last path segment,
`firstmate`; override it with `--name`.

Things to do by hand (all but the import check are **unverified**, see below):

1. **Import firstmate instead of gastown, not alongside it.** firstmate
   already imports gastown. Importing both would give you two of every role.
2. **Set merge ownership before attaching any rig.** The refinery prompt says
   the captain is the sole merge owner: when a change is ready to land, it
   tells the refinery to stop and file a `merge` decision with `gc firstmate
   decide`. It tells the refinery to resume only when a resolved decision for
   that exact change has the captain's recorded `approve` outcome; `hold`
   keeps it unlanded. The captain decides approve or hold; the refinery performs
   the merge only after an approve for that exact change. This v0 rail is not
   enforced against a refinery or other caller that skips the prompt: `resolve`
   does not verify who the caller is or bind an approval to one specific work
   item.
   Publishing a PR, closing a bead, and recording handoffs remain governed by
   the ordinary refinery workflow, so the captain can inspect the PR URL first.
3. **Give rigs the import too.** Rig-scoped roles (witness, refinery, polecat)
   come from imports at the rig level:

   ```toml
   # city.toml
   [defaults.rig.imports.firstmate]
   source = "https://github.com/trillium/gascity-packs/tree/main/firstmate"
   version = "sha:<commit>"
   ```

The intended command form is `gc <binding> <command>`, for example
`gc firstmate decide list`. However, on the live-checked Gas City
`0.15.1.trillium`, `gc --city <city> helm decide --help` and `resolve --help`
fell through to top-level help instead of dispatching; do not rely on these
commands in that version. If you choose another binding name, the Mayor prompt
renders that name into its instructions automatically.

## What it does

### 1. Communication contract (`template-fragments/firstmate-communication.template.md`)

The Mayor's prompt carries seven rules for everything the captain reads:

1. Address the human as "captain".
2. Lead with the outcome or the next action.
3. Translate internal terms (bead, polecat, refinery, convoy, rig...) into plain
   outcomes.
4. Ask only for approval, a merge, or a pick. Decide everything else.
5. Never claim running, stuck, done, or healthy without a check made this turn.
   A status line is an event, not the truth.
6. Make every final message standalone, with full PR URLs, and never a bare
   number.
7. Make wins visible.

### 2. Decision ledger (`commands/decide`, `commands/resolve`)

Each captain-needed decision is filed as a labeled bead **before** anyone is
asked. The Mayor prompt requires this
(`template-fragments/firstmate-decision-ledger.template.md`).

```bash
gc firstmate decide --kind merge --key pr-login-fix --binding firstmate \
  --what "Merge the login fix?" \
  --you-do "Open the linked change and reply 'approve' to let it land, or 'hold'." \
  --why-blocked "Only the captain approves a merge." \
  --artifact "https://github.com/org/repo/pull/12" \
  --stakes "Login stays broken for new users until merged; merge is revertable."

gc firstmate decide list            # what is waiting on the captain
gc firstmate resolve <id> --answer "merge it" --outcome approve   # record approval and close
```

- The bead carries labels `firstmate-decision`, `decision-kind:<kind>` and
  `decision-key:<key>`. The description holds the five fields
  **WHAT / WHAT YOU DO / WHY BLOCKED / ARTIFACT / STAKES**.
- `--kind` is a closed vocabulary: `approve`, `merge`, `pick`. Anything else is
  refused, since it is not a captain decision.
- A filing with any field missing or blank is refused. An `ARTIFACT` that is a
  bare number (`#11`) is refused, and every PR reference in all five fields
  must be a full HTTPS URL.
- `--key` is required and makes filing idempotent: an open decision with the
  same key is returned instead of filed twice.
- `--blocks <work-bead>` makes the work depend on the decision.
- `--binding <import-binding>` controls the resolve hint printed after filing;
  it defaults to `firstmate` and must be a plain identifier.
- `resolve` records the answer as a comment first, then closes. A `merge`
  decision also requires either `--outcome approve` or `--outcome hold`; an
  `approve` outcome tells the refinery that exact change may land, while
  `hold` tells it to keep the change unlanded. This is a recorded prompt-level
  policy: `resolve` does not verify who supplied the answer or bind approval to
  one specific work item. It refuses ids that are not ledger decisions or are
  already resolved, and it matches ids exactly (plain `gc bd` fuzzy-matches).

## Design

### Patch, not a full agent

The pack imports gastown and replaces the Mayor and refinery prompts with
pack-level patches:

```toml
[[patches.agent]]
name = "mayor"
prompt_template = "assets/prompts/mayor.template.md"

[[patches.agent]]
name = "refinery"
prompt_template = "assets/prompts/refinery.template.md"
```

**Finding: `[[patches.agent]]` can replace a prompt, so no full agent is
defined.** `prompt_template` is a patchable field, pack-level patches apply
after imports merge, and the path resolves relative to the patching pack
directory. Read from Gas City's source
(`internal/config/patch.go`, `internal/config/pack.go`) and its pack spec
("Pack-level patch paths in `prompt_template` ... resolve relative to the
patching pack directory"). Not yet run; see below.

Consequences worth knowing:

- Pack-level patches match the imported agents by their **local** names
  (`mayor`, `refinery`), not `gastown.mayor` or `gastown.refinery`. A missing
  target is a hard load error.
- The prompts live at `assets/prompts/*.template.md`, **not** under `agents/`.
  An `agents/refinery/` directory would define a second refinery that collides
  with the imported one. The `.template.md` suffix is what makes Gas City
  execute them as Go templates.
- Both prompts are copies of their gastown prompts with firstmate additions.
  A prompt patch replaces the whole prompt, so **upstream changes do not flow
  in automatically**. Each file header records the upstream commit; when you
  bump the pin in `pack.toml`, diff both by hand.
- A lighter Mayor-only alternative exists: `inject_fragments_append` could
  append the two fragments to the untouched upstream Mayor prompt, with no fork
  to maintain. It is not used because that would put the contract at the *end*
  of the prompt, and the contract has to frame the rest.

### Names under the `firstmate` binding

Importing firstmate re-stamps every gastown role under its binding (for example
`firstmate.polecat`). gastown's prompts use `{{ .BindingPrefix }}`, so they
follow. Wherever you wrote `gastown.polecat` (default sling targets, named
sessions) you will write `firstmate.polecat`.

### Current pack-spec constructs only

`schema = 2`, `[imports.*]` with a `source` plus `sha:` version pin,
`[[patches.agent]]`, `template-fragments/`, `commands/<name>/{run.sh,help.md}`,
and private files under `assets/`. No `[[agent]]`, `[formulas].dir`, top-level
`scripts/`, registry handles, or `path`/`ref`/`commit`/`hash` import keys.

### Layout

```text
firstmate/
├── pack.toml
├── README.md
├── assets/prompts/mayor.template.md
├── assets/prompts/refinery.template.md
├── template-fragments/
│   ├── firstmate-communication.template.md
│   └── firstmate-decision-ledger.template.md
└── commands/
    ├── decide/{run.sh,help.md}
    └── resolve/{run.sh,help.md}
```

### Roadmap layout: where scouts drop in

The layout leaves room for scouts (see "Deliberately not in v0") without moving
anything. Each addition is a new file or directory in a conventional location:

```text
firstmate/
├── formulas/scout.toml                     # the scout formula (no [formulas].dir needed)
├── commands/scout/{run.sh,help.md}         # gc firstmate scout ...: launch, check, relay
└── template-fragments/firstmate-scouts.template.md   # Mayor rules for scouts,
                                            # pulled into assets/prompts/mayor.template.md
```

Nothing in `pack.toml` has to change for the formula and command to load.

## Verified vs unverified

**Verified (static):**

- `pack.toml` parses as TOML and uses only pack-spec keys.
- `commands/*/run.sh` pass `shellcheck -s sh` and `sh -n`.
- The Mayor and refinery prompts and both fragments parse and render as Go templates
  (`missingkey=zero`), with and without a binding name, using gastown's real
  fragments at the pinned commit.
- `decide` and `resolve` behave as documented against a stand-in for `gc bd`:
  missing field, bad kind, malformed question, bare-number artifact, duplicate
  key, unknown id, double resolve, missing or invalid merge outcome, hold and
  approve outcomes, unowned caller.
- In a disposable live Gas City `0.15.1.trillium` city, importing firstmate
  under the custom `helm` binding passed `config-valid`.

**UNVERIFIED or unavailable in the checked live version:**

- That the patches find `mayor` and `refinery` and swap their prompts at
  runtime.
- The captain-only merge rail is prompt-level guidance to the refinery, not
  tamper-proof enforcement. It is not enforced against a refinery or any other
  caller that skips it; `resolve` does not verify the caller or bind an
  approval to one specific work item. The prompt rule is statically rendered
  and checked, but runtime enforcement has never run in a live city.
- That `prompt_template` resolves correctly when the pack sits in Gas City's
  remote-import cache rather than the city directory.
- The re-stamping of gastown roles as `firstmate.<name>`, the need for
  `[defaults.rig.imports.firstmate]`, and that importing firstmate *instead of*
  gastown is right.
- Command dispatch is unavailable in the live-checked Gas City
  `0.15.1.trillium`: `gc --city <city> helm decide --help` and
  `gc --city <city> helm resolve --help` fall through to top-level help. It is
  therefore unverified that commands appear as `gc <binding> <command>` with
  the environment the scripts expect (`GC_BIN`, `GC_AGENT`, `GC_RIG`) on a
  version where dispatch works.
- The real `gc bd` / `bd` behavior the scripts rely on: the flags
  `create --silent --description --labels --deps blocks:<id>`,
  `list --label --all --json --limit 0`, `comment`, `close --reason`; `--rig=`
  being accepted on those subcommands; and that `list --json` rows expose
  `id`, `status`, `title` and `created_at`. Misreads here fail closed (the
  commands refuse and print why), but they would make the ledger unusable.
- Whether `--deps blocks:<id>` works when the work bead lives in a different
  rig's store.

Prove these in a throwaway city before depending on the pack.

## Deliberately not in v0

These are known gaps, left for later:

- **Zero-token detection orders.** Scripts that detect stuck work, stale
  decisions or failed merges without spending model tokens. Today the Mayor has
  to look, by prompt rule only.
- **Fail-closed authority checks (`gc doctor`).** A closed vocabulary for
  authority flags, with doctor checks that fail when one is unreadable. The
  decision `--kind` vocabulary is the only closed vocabulary so far, and it
  guards filing, not authority.
- **Refuse-on-unlanded teardown.** Refusing to tear down a worker's workspace
  while it holds uncommitted or unmerged work.
- **Scripted merge gate (v0.1).** One merge script that reads live
  preconditions, binds the captain's identity, and records a persisted
  per-work-item merge-authority flag. v0 has only the refinery prompt-level
  rail.
- **Scouts: the Mayor launching read-only workers.** A scout is a worker whose
  deliverable is a **report, not a PR**, and which never writes to the project
  it studies. The Mayor must be able to launch one, and **may not relay a
  scout's result to the captain until a completion gate passes** (the report
  exists and was checked, not just a status line saying so). This is a
  roadmap item for a later version, not part of v0. It will arrive as a
  `scout` formula, a `gc firstmate scout` command and a Mayor-prompt
  fragment; the files go in the places shown under
  [Roadmap layout](#roadmap-layout-where-scouts-drop-in), so nothing in v0
  needs restructuring.
- **Proof that the answer came from the captain.** `resolve` records whatever
  `--answer` it is given; it neither verifies the caller nor binds an approval
  to a specific work item. v0 relies on the prompt rule that it be the
  captain's own words.

## License and upstream

The Mayor prompt is derived from gastown's, from
[gastownhall/gascity-packs](https://github.com/gastownhall/gascity-packs) at
commit `0f07496d2fa4fd957a8bea77dcfd653c5d4bcef5`. The firstmate additions are
marked `FIRSTMATE` in the prompt.

**Note:** the gascity-packs repository has no root `LICENSE` file at that
commit (gascity itself is MIT); confirm upstream terms before reusing the
derived prompt outside this repo.
