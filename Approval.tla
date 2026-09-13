-------------------------------- MODULE Approval --------------------------------
(*  Can an approved action run twice?

    A human approves one action. The agent may be resumed by several turns,
    each of which may try to spend the approval. This spec is parameterised by
    the three choices a team actually makes when implementing that:

      SpendMode   how the spend is recorded, relative to the effect
         "after"   check, do the effect, then record the spend    (replay-style resume)
         "before"  check, record the spend, then do the effect    (still a read-then-write)
         "cas"     compare-and-set the record, then do the effect (atomic spend)
      FreshView   TRUE  = the check re-reads the durable record
                  FALSE = the check uses the snapshot read when the turn started
      Serialize   TRUE  = only one turn at a time may be between claiming and finishing

    Run with TLC (see run.sh). Each .cfg file is one row of the table in the post.  *)

EXTENDS Naturals

CONSTANTS Turns,      \* the set of turns that may resume the approval, e.g. {t1, t2}
          SpendMode,  \* "after" | "before" | "cas"
          FreshView,  \* TRUE | FALSE
          Serialize   \* TRUE | FALSE

VARIABLES pc,     \* pc[t]   : which stage turn t is at
          log,    \* log     : the one durable approval record, "unspent" or "spent"
          view,   \* view[t] : what turn t saw the record as when it started
          eff     \* eff     : how many times the approved action has run in the world

vars == <<pc, log, view, eff>>

(*  Stages a turn passes through:
      idle -> ready -> claimed -> [armed] -> [acted] -> done
    "armed" exists only in "before" mode (spend recorded, effect pending);
    "acted" exists only in "after" mode (effect done, spend not yet recorded).  *)

Init == /\ pc   = [t \in Turns |-> "idle"]
        /\ view = [t \in Turns |-> "unread"]
        /\ log  = "unspent"
        /\ eff  = 0

\* What a turn sees when it checks: the live record, or the snapshot it started with.
\* A compare-and-set always reads the live record.
Sees(t) == IF FreshView \/ SpendMode = "cas" THEN log ELSE view[t]

\* Someone is between claiming and finishing (used only when Serialize = TRUE).
Busy == \E t \in Turns : pc[t] \in {"claimed", "armed"}

\* The turn starts: it reads the record once and remembers what it saw.
Restore(t) == /\ pc[t] = "idle"
              /\ pc'   = [pc   EXCEPT ![t] = "ready"]
              /\ view' = [view EXCEPT ![t] = log]
              /\ UNCHANGED <<log, eff>>

\* A turn may claim the approval when it is ready and sees the record as unspent.
\* With a compare-and-set ("cas"), the same step also marks the record spent.
Check(t) == /\ pc[t] = "ready"
            /\ Sees(t) = "unspent"
            /\ ~(Serialize /\ Busy)                \* if serialised: one turn at a time
            /\ pc'  = [pc EXCEPT ![t] = "claimed"]
            /\ log' = IF SpendMode = "cas" THEN "spent" ELSE log
            /\ UNCHANGED <<view, eff>>

\* "before" mode only: record the spend as a separate step, ahead of the effect.
Spend(t) == /\ SpendMode = "before"
            /\ pc[t] = "claimed"
            /\ pc'  = [pc EXCEPT ![t] = "armed"]
            /\ log' = "spent"
            /\ UNCHANGED <<view, eff>>

\* Calling the tool: one more effect in the world.
Effect(t) == /\ pc[t] = (IF SpendMode = "before" THEN "armed" ELSE "claimed")
             /\ eff' = eff + 1
             /\ pc'  = [pc EXCEPT ![t] = IF SpendMode = "after" THEN "acted" ELSE "done"]
             /\ UNCHANGED <<log, view>>

\* "after" mode only: record the spend once the effect has already happened.
Record(t) == /\ SpendMode = "after"
             /\ pc[t] = "acted"
             /\ pc'  = [pc EXCEPT ![t] = "done"]
             /\ log' = "spent"
             /\ UNCHANGED <<view, eff>>

Next == \E t \in Turns : Restore(t) \/ Check(t) \/ Spend(t) \/ Effect(t) \/ Record(t)

Spec == Init /\ [][Next]_vars

\* The two properties, checked in every reachable state.
AtMostOnce     == eff <= 1                       \* never two effects
NoResurrection == (eff >= 1) => (log = "spent")  \* once it ran, the record says so
=================================================================================
