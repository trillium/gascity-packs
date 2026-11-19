# firstmate merge-gate

The scripted gate between "ready to land" and landing. A caller that uses
this script lands only if it, re-reading live state, finds the captain's
approval of that exact change. It guards against mistakes; it is not a
security boundary: the captain id is a plain string, and an agent with `gc bd`
access can write the metadata and comments it checks.

```text
gc firstmate merge-gate bind-captain --id CAPTAIN_ID [--rig RIG]
gc firstmate merge-gate captain [--rig RIG]
gc firstmate merge-gate check WORK_BEAD_ID [--rig RIG]
gc firstmate merge-gate land WORK_BEAD_ID [--rig RIG] -- LANDING_COMMAND [ARGS...]
gc firstmate merge-gate revoke WORK_BEAD_ID --reason TEXT [--rig RIG]
```

**bind-captain** records who the captain is (a bead labeled
`firstmate-captain`). It refuses if a captain is already bound; changing the
binding means closing that bead by hand. `gc firstmate resolve` accepts a merge
decision only with `--captain` equal to this id.

**check** exits 0 and prints `MERGE AUTHORIZED` only when all of these hold
right now; otherwise it prints each `REFUSED:` reason and exits 1:

1. A captain is bound, and the work bead is open.
2. The work bead's `merge_authority` flag is `approved`, naming the bound
   captain, a decision id, and the approved head.
3. That decision is a resolved `merge` decision for this same work bead, whose
   comments record `OUTCOME: approve`, `CAPTAIN:` the bound captain, this
   `WORK:` and the approved `HEAD:`, and no `hold`.
4. The live PR (`metadata.pr_url`, else `existing_pr`) is open, not a draft,
   has no failing or pending check, and its head equals the approved head.
   With no PR, the branch's head on `origin` must equal it.
5. Any read that fails (store, GitHub) is a refusal, never a pass.

**land** runs `check`, records a comment on the work bead, then runs the
command after `--`. If `check` refuses, the command is not started.

**revoke** sets the flag to `revoked`. Anyone may revoke; `resolve` is the
intended way to grant.

Environment variables set by gc:
  GC_BIN         Path to the gc binary
  GC_AGENT       Calling agent (required)
  GC_RIG         Rig scope, when set
  GC_PACK_DIR    This pack's directory
