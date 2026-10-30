# BBmastery decision log

Implementation choices made in code `0.1.0-draft` where spec v1.0 left room for interpretation.
All are **P (proposed)** and need Dr. Rizuwan's confirmation or a separate labelled experiment.

| # | Topic | Spec ref | Choice in draft | Alternative |
|---|---|---|---|---|
| D01 | Gap through zone | §7 | Log `GAP_SKIPPED`, keep the candidate, require a fresh trend-side observation before another touch | Consume the candidate on a gap |
| D02 | Price already in or beyond the zone when armed | §7 | No touch until price is first observed on the trend side | — |
| D03 | REJECTION_CLOSE bar counting | §8.2 | Counts Entry bars whose close is after the touch time; the touch bar itself counts | Start from the bar after the touch |
| D04 | Structural extreme | §10.2 | Signal bar low/high, then each completed Setup bar, then live Bid ticks until entry | Include Ask for sells |
| D05 | Post-fill reconciliation, structural exits | §10.1–10.2 | SL is kept at the structural level; TP is recomputed from the actual fill × RR | Recompute both |
| D06 | Context check at touch | §8.1 | Context is re-checked at touch even when `ContextInvalidation=false` (spec §8.1 step 1) | Check only at arming |
| D07 | Opposite CT while a candidate is active | §9 | Uses the persistent opposite *candidate* on bar [1], not only an event | Event only |
| D08 | Deposits/withdrawals | §11 | Logged as `BALANCE_OP`; day-start equity **not** adjusted | Adjust the anchor |
| D09 | Protection-failure lock | §10.1 | In memory only; cleared by reloading the EA (manual reset) | Persist until a manual flag is set |
| D10 | Persistence in the Strategy Tester | §12 | Disabled in the tester; terminal global variables are used live | — |
| D11 | Uncertain order result | §12 | Stay in ORDER_PENDING; adopt the position if one appears, otherwise clear after `InpPendingTimeoutSec` without resending | — |
| D12 | Spread measure | §8.1 | Live `(ask − bid)/_Point` at the moment of touch | Symbol `SPREAD` property |
| D13 | Diagnostic ATR period / regime k | §16 | ATR14, k=5 (fixed before any evaluation) | Choose others before testing |
