# MoRizMa BBmastery EA — MQL5 draft

Implements the **CT-only research baseline** from
`research/specifications/MoRizMa_BBmastery_EA_Framework_v1.0.md`.

> **Status: DRAFT.** Not yet compiled, chart-validated or backtested. Compiling it proves
> nothing about profitability. Use demo/tester only (spec §22).

## Files

| Path (mirrors `MQL5/`) | Purpose |
|---|---|
| `Experts/MoRizMa/BBmastery/MoRizMa_BBmastery_EA.mq5` | EA: state machine, tick loop, journaling (§13–14) |
| `Indicators/MoRizMa/BBmastery_Diagnostics.mq5` | Overlay for visual validation (§18) — **use this first** |
| `Include/MoRizMa/BBmastery/Defines.mqh` | Enums, structs, reason codes |
| `Include/MoRizMa/BBmastery/Indicators.mqh` | BB20, LWMA5/10 H/L, EMA50, ATR handles (§4) |
| `Include/MoRizMa/BBmastery/Signals.mqh` | CT/CC, TRZ warnings, band regime (§6, §15, §16) |
| `Include/MoRizMa/BBmastery/Context.mqh` | Higher-timeframe context filter (§6.4) |
| `Include/MoRizMa/BBmastery/Candidates.mqh` | Zone geometry, tick retest/gap detection (§7) |
| `Include/MoRizMa/BBmastery/Risk.mqh` | Volume sizing, daily loss lock (§11) |
| `Include/MoRizMa/BBmastery/Execution.mqh` | Ownership, stops validation, CTrade wrapper (§12) |
| `Include/MoRizMa/BBmastery/Exits.mqh` | FIXED / STRUCTURE_RR / FROZEN_OUTER_BAND (§10) |
| `Include/MoRizMa/BBmastery/Persistence.mqh` | Terminal global-variable state store |
| `Include/MoRizMa/BBmastery/Journal.mqh` | Candidate-level CSV log (§17) |

## Install

Copy `Experts/`, `Indicators/` and `Include/` into the terminal's `MQL5/` data folder
(File → Open Data Folder), then compile the EA and indicator in MetaEditor (F7).

## Required inputs (refuses to start without them — U10)

- `InpMaxSpreadPoints`: symbol-specific spread limit
- FIXED exit: `InpFixedSLPoints`, `InpFixedTPPoints`
- STRUCTURE_RR / FROZEN_OUTER_BAND: `InpMaxStopPoints` (and ideally `InpMinStopPoints`)

All distances are in **points** (`_Point`), never pips. No defaults are pre-approved.

## Implemented vs. not

| Module | State |
|---|---|
| CT candidate + FIRST_TRANSITION / EVERY_QUALIFYING_BAR | Implemented |
| CC, TRZ warnings, band regime | Logged as diagnostics only; never traded |
| Context filter OFF / MIDDLE / MIDDLE+EMA50, context invalidation | Implemented |
| Zones LIVE / FROZEN_SIGNAL / LAST_CLOSED, Bid reference, tolerance | Implemented |
| Entry TOUCH / REJECTION_CLOSE | Implemented |
| Exit FIXED / STRUCTURE_RR / FROZEN_OUTER_BAND, opposite-CT exit | Implemented |
| FIXED_LOT / EQUITY_RISK sizing, margin check, daily lock | Implemented |
| Netting ownership refusal, restart reconciliation, partial-fill logging | Implemented |
| TS reversal, CC/TRZ entries, BEP/trailing/partial close, session filter | **Not implemented** (deferred/U) |
| Grid / recovery / hedging / AIO | **Excluded** |

## Journal

The EA writes `MoRizMa_BBmastery_<symbol>_<magic>.csv` to `Common\Files` (or the agent's
`MQL5\Files` when `InpJournalCommon=false`). It is an **event log keyed by `setup_id`**:
ARMED, NOT_ARMED, CANCELLED, REJECTED, GAP, TOUCH, SUBMITTED, FILLED, PROTECTED, CLOSED,
plus CC_DIAG / TRZ_DIAG / LOCK / DAY_ROLL / BALANCE_OP. Group rows by `setup_id` to get one
record per candidate. MAE/MFE use liquidation quotes and exclude fees (`mae_mfe_basis`).

## Validation checklist before any backtest (spec §18)

1. Compile both files; fix any compiler errors (the code has not been through MetaEditor yet).
2. Check that the diagnostic indicator's BB/MA lines match MT5's native Bollinger Bands /
   Moving Average on the same chart (buffer mapping).
3. Use the visual tester to compare `ARMED` journal timestamps against the indicator's CT arrows.
4. Check: no arrow on the forming bar; consecutive qualifying bars give one event; buy/sell
   rules mirror each other; no entry on the signal candle; expiry/opposite CT are processed
   before a touch on the same tick.
5. Restart test: stop and restart the EA with an open position and with a pending candidate.
6. Only then run *Every tick based on real ticks* for run family A (§19).

See `research/decision_log.md` for implementation choices made where the spec was silent.
