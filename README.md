# tla-agent-approval

Can an approved action run twice? A fifty-line TLA+ spec of the confirmation step almost every
agent has, parameterised by the three choices a team actually makes when implementing it, with
the five configurations from the post and a script that checks them.

Companion to [*Your agent is a distributed system. Check it like one.*](https://1uke.io/writing/your-agent-is-a-distributed-system/)

## The question

A human approves one action. The agent may be resumed by several turns, each of which may try to
*spend* the approval. Two properties must hold in every reachable state:

```tla
AtMostOnce     == eff <= 1                       \* never two effects
NoResurrection == (eff >= 1) => (log = "spent")  \* once it ran, the record says so
```

The spec has one durable record (`log`, `unspent` or `spent`), a stage per turn (`pc[t]`), the
snapshot each turn read when it started (`view[t]`), and a count of effects in the world (`eff`).
Three switches select the design:

| Switch | Values | Meaning |
| --- | --- | --- |
| `SpendMode` | `"after"` · `"before"` · `"cas"` | record the spend after the effect, before it, or compare-and-set it in the same step as the check |
| `FreshView` | `TRUE` · `FALSE` | the check re-reads the durable record, or uses the snapshot the turn started with |
| `Serialize` | `TRUE` · `FALSE` | at most one turn at a time between claiming and finishing |

## Run it

Java 11+ and the TLA+ tools jar:

```sh
curl -LO https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar
./run.sh
```

`run.sh` checks each configuration against each property separately (TLC stops at the first
violation, and `NoResurrection` fails earlier than `AtMostOnce`), and prints:

```
1_after_snapshot       AtMostOnce: violated in 7 steps   NoResurrection: violated in 4 steps
2_after_fresh          AtMostOnce: violated in 7 steps   NoResurrection: violated in 4 steps
3_before_fresh         AtMostOnce: violated in 9 steps   NoResurrection: holds
4_cas                  AtMostOnce: holds                 NoResurrection: holds
5_before_serialized    AtMostOnce: holds                 NoResurrection: holds
```

Every *violated* leaves a `_<row>_<property>.log` whose trace is the interleaving that breaks
the property, step by step. Every *holds* is a proof for two turns: every interleaving was
enumerated. A row takes a couple of seconds.

| Configuration | How the spend is implemented | Can the action run twice? |
| --- | --- | --- |
| `1_after_snapshot` | after the effect, using the snapshot the turn started with | yes — 7 steps |
| `2_after_fresh` | after the effect, re-reading the record first | yes — 7 steps |
| `3_before_fresh` | before the effect, re-reading the record first | yes — 9 steps, a lost update |
| `4_cas` | compare-and-set the record, then the effect | no |
| `5_before_serialized` | before the effect, one turn at a time | no |

To check your own design, copy a `.cfg`, set the three switches to what your code does, and run
TLC on it directly:

```sh
java -cp tla2tools.jar tlc2.TLC -workers 1 -config my_design.cfg Approval.tla
```

(`-workers 1` keeps the reported counterexample the shortest one.)

## The rule the table proves

> Spend the approval atomically, spend it before you act, and never resume from a view older
> than the last spend.

Rows 1–2 break *spend before you act*: for a window the record says *unspent* about an action
that ran, and a turn that restores inside that window runs it again. Row 3 breaks *spend
atomically*: both turns read *unspent*, both write *spent*, both execute — a read-modify-write
race. Rows 4–5 are the two ways of making the spend atomic, and both record it before the
effect.

## The same properties against real code

The spec checks a design. To check an implementation, drive the real resume path with a fake
backend that counts effects, and assert the same two properties — for example with
[Hypothesis](https://hypothesis.readthedocs.io/en/latest/stateful.html)'s `RuleBasedStateMachine`:

```python
class ApprovalMachine(RuleBasedStateMachine):
    """Drive YOUR resume path; assert the properties, not the implementation."""

    @rule()
    def restore_and_claim(self):
        self.turns.append(agent.restore(self.approval_id))

    @rule()
    def execute(self):
        for t in self.turns:
            t.run()          # your real code path, fake backend underneath

    @invariant()
    def at_most_once(self):
        assert backend.effect_count(self.approval_id) <= 1

    @invariant()
    def no_resurrection(self):
        if backend.effect_count(self.approval_id) >= 1:
            assert not agent.restorable(self.approval_id)
```

Fake three things — the backend, the LLM (scripted decisions), and the client connections — and
keep the real code for restore, claim, spend and dispatch. A counterexample from TLC is the
sequence of rules to replay as a regression test.

## Files

```
Approval.tla              the spec, commented for readers new to TLA+
1_after_snapshot.cfg      one configuration per row of the table
2_after_fresh.cfg
3_before_fresh.cfg
4_cas.cfg
5_before_serialized.cfg
run.sh                    checks every row against every property
```

MIT.
