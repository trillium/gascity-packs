# firstmate decide

File a decision that needs the captain, in the decision ledger. File it here
**before** you ask the captain anything.

```text
gc firstmate decide --kind approve|merge|pick --what TEXT --you-do TEXT \
    --why-blocked TEXT --artifact TEXT --stakes TEXT \
    --key KEY [--blocks WORK_BEAD_ID] [--rig RIG]
gc firstmate decide list [--all] [--rig RIG]
```

A decision is a bead labeled `firstmate-decision`, `decision-kind:<kind>`, and
`decision-key:<key>`. Its description holds five fields:

| Flag | Field | Contents |
|------|-------|----------|
| `--what` | WHAT | The decision in one plain sentence, ending in a question mark. |
| `--you-do` | WHAT YOU DO | The exact action the captain takes. |
| `--why-blocked` | WHY BLOCKED | Why it cannot proceed without them. |
| `--artifact` | ARTIFACT | What to look at: a full URL or path, never a bare number; every PR reference in any field must use a full HTTPS URL. |
| `--stakes` | STAKES | Cost of waiting, cost of a wrong answer, whether it can be undone. |

All five are required; a filing with a missing field is refused.

`--kind` is a closed vocabulary: `approve`, `merge`, or `pick`. Anything else is
not a captain decision, and the command refuses it.

`--key` is required and makes filing idempotent: if an open decision with the
same key exists, its id is printed and nothing new is filed. Keys use letters,
digits, `.`, `_` and `-`.

`--blocks WORK_BEAD_ID` makes that work item depend on the decision, so it is
not picked up until the decision is closed.

`--rig` files (or lists) in that rig's store instead of the city's. With no
flag, `GC_RIG` is used when set; otherwise the city store.

`list` prints open decisions oldest first as `id`, `status`, `title`;
`--all` includes resolved ones.

Close a decision with `gc firstmate resolve`; a `merge` decision also requires
`--outcome approve|hold`. If the pack was imported under a different binding
name, replace `firstmate` with that name.

Environment variables set by gc:
  GC_BIN         Path to the gc binary
  GC_AGENT       Calling agent (required)
  GC_RIG         Rig scope, when set
  GC_CITY_PATH   Absolute path to the city root
  GC_PACK_DIR    Absolute path to this pack's directory
