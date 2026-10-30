# MoRizMa BBmastery EA Framework

Version: 1.0 — research and implementation specification  
Prepared for: Dr. Mohd Rizuwan Mamat  
Date: 30 October 2026  
Target: MetaTrader 5 / MQL5  
Status: Proposed research implementation; no EA has been coded, compiled or backtested under this specification.

## 1. Purpose and boundaries

Develop a reproducible EA inspired by Road to FTT / Gero Azrul's BBmastery approach. Establish the quality of individual setups before introducing recovery, grid, hedging or basket management.

This document distinguishes the historical teaching from engineering decisions needed to make it executable. It is not an official Road to FTT specification, endorsement or claim of profitability. The historical text may differ from later teaching.

Evidence labels:

- **R — researched:** identifiable in the sources listed in section 23.
- **P — proposed:** a mechanical interpretation or implementation decision introduced here.
- **U — unresolved:** requires confirmation or a separately labelled experiment.

Unless explicitly labelled R, all algorithms, defaults, thresholds, architecture and tests below are P. Their inclusion does not mean Dr. Rizuwan has already approved them as the final trading rules.

## 2. Historical foundation — concise evidence summary

The 2017 author-attributed text describes default BB20; LWMA5/10 High and Low; EMA50 Close. CTU closes above both High MAs and middle BB; CTD closes below both Low MAs and middle BB. CC closes outside an outer band. EC enters a later opposing-MA retest, potentially intrabar. TRZ uses an MA reaching outside a band, followed by reversal and retest; TS follows the preceding reversal sequence. Exits vary: opposing MAs, previous CT reference, middle/outer bands, continuation management or opposing CT invalidation. These are descriptions, not guarantees. [S1]

Road to FTT's public posts describe top-down mapping, higher-timeframe context and lower-timeframe entry refinement. They distinguish aligned-trend, proactive retracement and systematic approaches. [S2–S4]

This summary is the sourced foundation. The detailed formalisation below is an independently proposed implementation, not a reproduction of all discretionary teaching.

## 3. Development scope

| Module | Purpose | Initial status |
|---|---|---|
| CT detector | Identify directional candidate candles | Implement |
| CC detector | Record continuation events | Diagnostic first; separate entry experiment |
| EC executor | Trade a later MA-zone pullback | Implement for CT |
| TRZ reversal | Detect and trade reversal sequences | Diagnostic only; entry disabled |
| TS reversal | Detect potential new-trend sequence | Deferred pending precise rules |
| Band regime | Record band width and slope | Diagnostic; filter disabled |
| Multi-timeframe context | Record direction and optional alignment | Implement |
| Position/risk manager | Enforce exposure and exits | Implement |
| Grid/recovery/hedging | AIO management integration | Excluded from initial experiments |

Do not silently add EC359, MA Mirror, BL Magnet or other advanced names as if their algorithms were established. Their definitions remain U.

## 4. Indicator specification

| Indicator | Period | Method / applied price | Shift | Status |
|---|---:|---|---:|---|
| Bollinger Bands | 20 | Close; deviation 2.0 | 0 | Period R; exact configuration P pending template verification |
| High MA fast | 5 | Linear Weighted / High | 0 | Method, period, price R; shift P |
| High MA slow | 10 | Linear Weighted / High | 0 | Method, period, price R; shift P |
| Low MA fast | 5 | Linear Weighted / Low | 0 | Method, period, price R; shift P |
| Low MA slow | 10 | Linear Weighted / Low | 0 | Method, period, price R; shift P |
| Black Line | 50 | Exponential / Close | 0 | Method, period, price R; shift P |

Use native MT5 indicators after checking their current official documentation during implementation. Verify buffer mapping against plotted charts; never assume buffer numbers from memory. Release handles on deinitialisation. Skip evaluation when history, handles or copied data are incomplete.

Notation:

```text
O, H, L, C = candle open, high, low, close
U, M, D    = upper, middle, lower Bollinger Band
H5, H10    = LWMA High values
L5, L10    = LWMA Low values
E50        = EMA50 Close
[1]        = most recently completed candle on the specified timeframe
[0]        = current forming candle
```

## 5. Timeframes and information availability

Initial research preset: Context H4 / Setup H1 / Entry M15. This is P, not a required original combination.

Additional configurations must be separate runs:

| Preset | Context | Setup | Entry |
|---|---|---|---|
| Slower comparison | D1 | H4 | H1 |
| Initial baseline | H4 | H1 | M15 |
| Fast research | M15 | M5 | M1 |

Use completed candles for context, signal formation and invalidation. At any decision timestamp, use only higher-timeframe candles whose closing time has already occurred. Do not retrieve the eventual closing value of a higher-timeframe candle still forming at that timestamp.

Entry timeframe controls optional confirmation and diagnostics. Touch entry follows ticks against the Setup timeframe zone; it does not require a new Entry timeframe bar.

## 6. Mechanical signal definitions

### 6.1 CT candidate

```text
BullCandidate = C[1] > max(H5[1], H10[1], M[1])
BearCandidate = C[1] < min(L5[1], L10[1], M[1])
```

Optional candle-colour filter: require C > O for bull and C < O for bear. Default OFF because this additional requirement remains a design choice.

This detector identifies a candidate from candle location. It does not claim to validate the complete historical TRZ/EZ/TS sequence. Log FullSequenceVerified=false until that module exists.

### 6.2 Event versus persistent condition

Default EventMode=FIRST_TRANSITION:

```text
NewBullCT = BullCandidate[1] AND NOT BullCandidate[2]
NewBearCT = BearCandidate[1] AND NOT BearCandidate[2]
```

An alternative EVERY_QUALIFYING_BAR may be tested separately. Do not refresh expiry indefinitely whenever another same-direction candle qualifies. Default policy: retain the original candidate until entry, expiry or invalidation.

### 6.3 CC candidate

```text
BullCC = C[1] > U[1]
BearCC = C[1] < D[1]
```

Record CC independently of CT; the two may coexist. Avoid duplicate orders from one candle. CC-origin entries are disabled in the initial CT-only baseline, then evaluated as a separate experiment.

### 6.4 Context direction

Proposed default filter:

```text
BullContext = Context.C[1] > Context.M[1]
              AND Context.C[1] > Context.E50[1]
BearContext = Context.C[1] < Context.M[1]
              AND Context.C[1] < Context.E50[1]
Otherwise = neutral
```

Modes: OFF, MIDDLE_BAND_ONLY, MIDDLE_AND_EMA50. Default MIDDLE_AND_EMA50 for the filtered preset. Also run an unfiltered baseline to quantify its effect. Neutral blocks new entries; it is not an automatic reversal signal.

## 7. Entry zone and retest geometry

Buy zone: [min(L5,L10), max(L5,L10)] on Setup timeframe.  
Sell zone: [min(H5,H10), max(H5,H10)] on Setup timeframe.

Zone modes:

- LIVE: current Setup indicator values updated on ticks; default.
- FROZEN_SIGNAL: values saved when the signal closes; separate experiment.
- LAST_CLOSED: latest completed Setup candle values; separate experiment.

Historical signals remain immutable even when a LIVE entry zone moves.

Reference chart price is Bid for tick-touch detection, matching ordinary Bid-based chart history. Buy execution occurs at Ask and sell execution at Bid. Record reference touch and executable price separately. Do not compare Ask to a Bid-derived historical zone without an explicit alternate policy.

Default tolerance=0 points; optional tolerance must be expressed in points or price units and recorded. Never infer a gold pip convention from forex digits.

A candidate is eligible only after its signal candle closes. Require the reference price to have been on the intended trend side of the zone before accepting a return:

- Buy: observe price above zone high, then a return into the zone.
- Sell: observe price below zone low, then a return into the zone.

Recompute relative position for LIVE zones and log it. A moving zone reaching stationary price is accepted under LIVE semantics; distinguish this diagnostically from price travelling into a stationary zone.

Gap policy: if a tick jumps entirely through the zone without an observed executable opportunity, default SKIP_GAP. Do not invent a fill at the skipped MA price. In real trading, stops and market fills can still slip.

## 8. Entry models

### 8.1 TOUCH — initial model

At the first eligible tick inside the zone:

1. Verify active candidate, age, current context and no invalidation.
2. Verify exposure, daily lock, spread, session and market availability.
3. Compute intended entry from current executable quote.
4. Compute SL, TP, volume and prospective risk.
5. Reject if any value violates broker or research constraints.
6. Submit one market request and wait for confirmed transaction results.

The first eligible touch consumes the candidate under the default policy, even if a spread/risk filter blocks the trade. Log the rejection. An alternative retry-until-expiry policy is a separate experiment.

### 8.2 REJECTION_CLOSE — optional variant

After a recorded touch, require a completed Entry timeframe candle to close back above the relevant zone boundary for a buy, or below it for a sell. Save the zone boundary at touch so confirmation cannot change retrospectively. Default confirmation timeout=3 Entry bars. Enter at the next available quote after confirmation, subject to all filters. This is an added rule, not established original teaching.

## 9. Candidate expiry and invalidation

Proposed expiry: 8 completed Setup bars after signal closure. Expires at the close of the eighth subsequent Setup candle; no entry on or after that timestamp.

Before entry, cancel on:

- Opposite CT candidate on a completed Setup candle.
- Context no longer permits the direction when ContextInvalidation=ON.
- Expiry, daily risk lock, position ownership conflict or explicit manual disable.

At an opposite CT event, cancel the old candidate and arm the new direction only if its own filters pass. No automatic reversal trade.

Bar-event ordering: apply newly completed-bar invalidation and expiry before considering that tick's touch. Same-direction events do not reset an existing candidate by default.

## 10. Exact exit policies for experiments

Use one selected exit policy per run. Do not choose the most favourable policy after seeing a trade's outcome.

### 10.1 FIXED — entry-quality baseline

User supplies FixedSLPoints and FixedTPPoints for the selected symbol. No universal distance is pre-approved. Refuse execution if either is zero or invalid.

```text
Buy:  SL = actual_fill - SL_distance; TP = actual_fill + TP_distance
Sell: SL = actual_fill + SL_distance; TP = actual_fill - TP_distance
```

Attach valid provisional protection at submission based on the requested quote where supported; after fill, reconcile to actual fill subject to broker restrictions. Do not intentionally leave a filled position unprotected while waiting for a perfect distance. If protection cannot be established, attempt immediate closure and lock new entries pending reconciliation.

### 10.2 STRUCTURE_RR — separate experiment

Buy SL: lowest completed Setup low from the signal candle through the latest completed Setup candle before entry, also including the observed current-candle low up to entry, minus buffer.

Sell SL: corresponding highest high plus buffer. Do not use the current candle's eventual full high/low. Update observed extrema causally on ticks.

TP distance = initial actual-fill-to-SL distance × RRMultiple. Initial proposed RRMultiple=1.5; test a small predefined set rather than exhaustive optimisation. Reject entries outside user-configured minimum/maximum stop distance.

### 10.3 FROZEN_OUTER_BAND — separate experiment

At entry, freeze the latest completed Setup upper BB for a buy, lower BB for a sell. Reject a target already on the wrong side of executable entry or too close after costs. Use STRUCTURE_RR's SL construction but replace its TP. This is a testable approximation, not an assertion that original targets are frozen.

### 10.4 Optional signal exit

OppositeCTExit may be added to any policy in a separate run. Exit at the next available quote after a completed opposite Setup CT; retain the hard SL. Context-loss exit is a different option and defaults OFF for open positions.

### 10.5 Later management

BEP, trailing, partial close and dynamic-band targets default OFF. Add one at a time after selecting a stable baseline. BEP must include estimated spread/commission/swap and cannot guarantee a net-positive fill. Never widen a hard SL as a recovery action.

If broker SL/TP closes first, process that transaction; do not send a second close. No same-tick reversal or re-entry after closure. Require a new eligible setup.

## 11. Risk and volume

Modes: FIXED_LOT for comparisons; EQUITY_RISK for normalised experiments. Suggested research risk input=0.25% equity per trade, explicitly P and not a promise of suitability. Initial maximum positions=1 per EA/symbol, no pyramiding.

Use account-currency estimated loss from entry to stop at a valid reference volume, then scale. Include an estimated commission allowance. Round volume down to the broker step and respect minimum/maximum volume. Reject if rounding to minimum would exceed the risk budget; never round upward to force a trade.

Before submitting, validate free margin, total planned exposure and stops/freeze constraints using current broker metadata. Use proper trade-calculation APIs during implementation; do not assume tick value is constant across symbols or currencies.

Daily protection uses broker-server day boundaries:

```text
day_start_equity = equity recorded at the day's first valid snapshot
daily_loss = max(0, day_start_equity - current_equity)
lock when daily_loss >= day_start_equity * DailyLossLimitPct / 100
```

Proposed DailyLossLimitPct=2.0; it is an experimental safety control, not a prop-firm compliance model. Default breach action: cancel candidates, close EA-owned positions, persist lock until next day. Account equity reflects other activity; the EA must not close unrelated positions. Log deposits/withdrawals and require a declared adjustment policy. If first started mid-day without history, label the anchor a partial-day baseline.

## 12. Execution and account behaviour

- Unique magic number, strategy version and setup ID on requests/logs.
- Never modify manual or other-EA positions.
- On netting accounts, refuse new entries when the symbol already has an unrelated position; ownership cannot be separated safely by ticket magic alone.
- One in-flight request per setup. Reconcile orders, deals and positions before retrying.
- Persist state across terminal restart and inspect broker state before resuming.
- A market-closed or insufficient-margin error is not permission for unlimited retries.
- Handle partial fills explicitly: protect filled volume; record residual; do not automatically top up in v1.
- On missing data/disconnection, stop new entries. Server-side protection remains essential because local signal exits cannot execute while offline.
- Broker rejection, slippage and gaps must be included in the report; requested prices are not fills.

Session filters default OFF. When enabled, define broker-server time, daylight-saving handling and weekend rollover explicitly. Spread limit is a required symbol-specific input; no universal points threshold.

## 13. State machine

| State | Event | Action / next state |
|---|---|---|
| IDLE | Eligible new CT | Save candidate → WAIT_RETEST |
| WAIT_RETEST | Expired / invalidated | Record reason → IDLE |
| WAIT_RETEST | Touch, confirmation mode | Save touch → WAIT_CONFIRM |
| WAIT_RETEST | Touch, touch mode | Validate → ORDER_PENDING or consumed rejection |
| WAIT_CONFIRM | Confirmed within timeout | Validate → ORDER_PENDING |
| WAIT_CONFIRM | Timeout / invalidation | Cancel → IDLE |
| ORDER_PENDING | Confirmed fill | Protect position → POSITION_OPEN |
| ORDER_PENDING | Uncertain result | Reconcile; block duplicate submission |
| POSITION_OPEN | Exit condition | CLOSE_PENDING |
| CLOSE_PENDING | Closure confirmed | Log outcome → IDLE |
| Any | Daily breach / unsafe state | LOCKED; reconcile exposure |
| LOCKED | Valid reset | Reconcile → IDLE |

Direction is candidate metadata, not a separate strategy instance. Use terminal trade events for authoritative fills and closure.

## 14. Tick-loop outline

```text
OnInit:
  validate inputs and account mode
  create indicator handles; load persistent state
  reconcile live orders/positions; initialise daily anchor

OnTick:
  reconcile transaction state and daily protection
  manage existing position protection and scheduled exits
  if unsafe or locked: return
  if new completed Setup bar:
    apply expiry and opposite-signal invalidation
    record CT/CC events and context snapshot
    arm eligible candidate if no owned exposure/request
  if candidate eligible:
    update causal extrema and entry zone
    detect retest/confirmation
    validate and submit at most one request

OnTradeTransaction:
  update authoritative fills, protection and closure
  record costs; reconcile uncertain submissions

OnDeinit:
  persist state; release handles
```

## 15. Experimental reversal modules

TRZ and TS must remain disabled for orders until labelled chart examples and precise sequencing rules are agreed. A possible TRZ diagnostic predicate is:

```text
SellWarning = max(H5[1], H10[1]) >= U[1]
BuyWarning  = min(L5[1], L10[1]) <= D[1]
```

This is only a proposed warning detector. Resolve which MA qualifies, touching tolerance, persistence, reverse-candle definition, retest level, timeout and SL before enabling trades. Do not treat a warning as immediate permission to fade a strong trend.

For TS, first specify the stored preceding TRZ/EZ events, allowable bar gaps, inside-band test, reverse candle and retest trigger. No fabricated universal rule should be inserted to fill these gaps.

## 16. Band-regime diagnostics

Record, initially without filtering:

```text
width = U - D
normalised_width = (U - D) / ATR
middle_slope = (M[1] - M[1+k]) / (k * ATR[1])
width_change = width[1] / width[1+k] - 1
```

Require positive denominators and sufficient history. ATR here is an added diagnostic, not an original BBmastery requirement. Choose k and percentile windows before evaluating results. Flat/squeeze/expansion/trend labels remain experimental until thresholds are locked. Wider bands do not guarantee continuation; narrow bands do not guarantee breakout direction.

## 17. Logging and explanation

Write candidate-level records, including rejected setups, so the analysis is not limited to winners or executed trades.

Required fields:

```text
run_id, code_version, parameter_hash, symbol, broker, server_timezone
setup_id, setup_origin, signal_time, direction, context_direction
timeframe_context, timeframe_setup, timeframe_entry
signal_OHLC, signal_MAs, signal_bands, signal_EMA50
zone_mode, zone_at_signal, zone_at_touch, reference_touch_price
bid, ask, spread_points, band_width, slope, session
signal_age_bars, full_sequence_verified, filter_results
decision, rejection_reason, order_ticket, deal_id, actual_fill
initial_SL, initial_TP, actual_volume, planned_risk_currency
exit_time, actual_exit, exit_reason, commission, swap, net_profit
MAE_currency, MFE_currency, initial_R, net_R, holding_duration
```

Measure MAE/MFE using executable liquidation quotes and observed prices. State whether accrued fees are included. Net profit must include entry and exit commission, swap and realised trading P/L.

Suggested reason codes: CONTEXT_CONFLICT, EXPIRED, OPPOSITE_CT, SPREAD_HIGH, GAP_SKIPPED, STOP_INVALID, TARGET_INVALID, VOLUME_BELOW_MIN, MARGIN_LOW, OWNERSHIP_CONFLICT, DAILY_LOCK, DATA_NOT_READY, BROKER_REJECT, TOUCH_CONSUMED, PROTECTION_FAILURE.

For future MMIA integration, expose separate direction and readiness fields:

```text
direction = +1 / -1; valid only when has_candidate=true
regime_direction = +1 / -1; valid only when regime_known=true
entry_ready = true / false
setup_type, setup_age, rejection_reason
```

Do not force a buy/sell value during neutral or missing-data periods. A validity flag preserves the user's binary directional convention without inventing actionable signals.

## 18. Validation before profitability testing

Build a diagnostic indicator or overlay before the executor. Show immutable CT/CC markers, active candidate, live/frozen zone, context and cancellation reasons.

Use a manually reviewed sample containing buys, sells, trends, ranges, gaps, spread spikes and invalidations. Include all selected cases, not only attractive examples. Compare timestamps and levels; document disagreements.

Meaningful implementation tests include:

- Boundary equality versus strict crossing; no duplicate event on consecutive qualifying candles.
- Correctly mirrored buy/sell rules and zones.
- No same-signal-candle retest entry.
- No higher-timeframe or intrabar look-ahead.
- Expiry and opposite CT processed before touch on a shared timestamp.
- Restart with pending request, partial fill or open position does not duplicate exposure.
- Volume step/minimum and account-currency risk calculations across instrument types.
- Daily lock persistence, rollover, protection failures and netting ownership conflicts.

## 19. Backtest study design

Use MT5 Every tick based on real ticks for tick-sensitive entries. Record actual data coverage and any missing-tick or model limitations. Open-prices-only results are not adequate evidence for this design.

Predeclare chronological development, validation and untouched holdout periods. Avoid selecting parameters on the holdout and then reporting it as unseen. Include realistic costs and stress spreads/slippage. Do not assume historical fills perfectly reproduce live execution.

| Run family | Entry | Context | Exit | Purpose |
|---|---|---|---|---|
| A | CT touch | OFF | Fixed | Establish unfiltered entry baseline |
| B | CT touch | ON | Fixed | Isolate context effect |
| C | CT rejection-close | ON | Fixed | Isolate confirmation effect |
| D | Selected entry | Selected context | Structure RR | Compare exit logic |
| E | Same selected entry | Same context | Frozen outer band | Compare band target |
| F | CC-origin touch | Same context | Same baseline exit | Test continuation-origin entries |
| G | Selected stable configuration | Same | Add one management feature | Isolate BEP/trailing contribution |

Control trade risk/exposure when comparing exits with different stop distances. Report both fixed-volume and risk-normalised results when their interpretations differ. Use a small, declared parameter grid and report all tested configurations to expose selection bias.

## 20. Required reporting

Report net return, equity drawdown in currency and percentage, PF, recovery factor with its exact denominator, expected net trade, win rate, average win/loss, trade count, exposure, losing streak, MAE/MFE, holding time and cost sensitivity. If reporting Sharpe, define return frequency, annualisation and risk-free assumption.

Break down results by long/short, setup origin, context, band regime, session and timeframe preset. Show sample sizes for every subgroup. Do not infer a dependable edge from a tiny favourable subgroup.

Use confidence intervals or resampling that respects dependence between nearby trades where practical. Check nearby parameter values; a single sharp optimum is weaker evidence than a stable region. A high win rate alone does not establish positive expectancy or acceptable tail losses.

## 21. Suggested MQL5 project structure

```text
Experts/MoRizMa/BBmastery/MoRizMa_BBmastery_EA.mq5
Include/MoRizMa/BBmastery/Indicators.mqh
Include/MoRizMa/BBmastery/Signals.mqh
Include/MoRizMa/BBmastery/Candidates.mqh
Include/MoRizMa/BBmastery/Context.mqh
Include/MoRizMa/BBmastery/Risk.mqh
Include/MoRizMa/BBmastery/Execution.mqh
Include/MoRizMa/BBmastery/Exits.mqh
Include/MoRizMa/BBmastery/Persistence.mqh
Include/MoRizMa/BBmastery/Journal.mqh
Indicators/MoRizMa/BBmastery_Diagnostics.mq5
research/specifications/
research/chart_examples/
research/presets/
research/reports/
research/decision_log.md
```

Version strategy logic and experiment presets independently. Preserve baseline source, terminal build, broker symbol specification, data dates, settings and reports together. Never overwrite the control version after a promising optimisation.

## 22. Implementation handover and acceptance

Instruction for Hermes/Codex:

> Implement the proposed CT-only baseline in this document as a research EA. Read the complete specification first. Keep R, P and U distinctions. Create diagnostics before order execution. Resolve routine programming issues autonomously, but do not invent unresolved trading rules or enable deferred modules. Verify current MQL5 APIs against official documentation. Compile, validate causal signal timing, run the specified tests and produce reproducible real-tick reports. Do not deploy to a live account or claim profitability from compilation or one backtest.

Milestones:

1. Confirm original indicator template and collect annotated examples where available.
2. Implement and visually validate diagnostics.
3. Implement CT touch with fixed exits and one-position control.
4. Validate execution, restart and risk behaviour.
5. Run baseline comparisons and untouched-period evaluation.
6. Test structural/band exits and CC-origin entries independently.
7. Consider TRZ/TS only after their unresolved rules are specified.
8. Consider AIO integration after standalone evidence is satisfactory.

Acceptance requires: no unexplained diagnostic disagreements; no look-ahead; no duplicate requests; protected positions; broker-aware risk sizing; complete rejection logs; reproducible settings/results; and explicit disclosure of data or execution limitations. Compilation alone does not satisfy acceptance. No performance threshold is invented in this document; agree return/drawdown objectives before selecting a production candidate.

Open decision register:

| ID | Decision | Current proposed handling |
|---|---|---|
| U01 | Original BB settings and shifts | Verify template; proposed settings in section 4 |
| U02 | Complete sequence compulsory for CT? | Simplified candidate mode; flag unverified |
| U03 | Candle body-cross and colour requirements | Strict close location; colour filter OFF |
| U04 | Current versus frozen retest zone | LIVE baseline; compare separately |
| U05 | Repeated same-direction signals and touches | First-transition candidate; first eligible touch |
| U06 | Original stop and target selection | Separate explicit experimental policies |
| U07 | Higher-timeframe override hierarchy | Deterministic filter; no discretionary override |
| U08 | TRZ/TS exact sequencing | Orders disabled |
| U09 | EC359 / Mirror / Magnet | Not implemented |
| U10 | Instrument, costs and distance inputs | Must be supplied before an executable test |

## 23. Sources and provenance

These sources were consulted in the preceding research conversation. This framework does not claim fresh verification of updated teaching on its preparation date. Author-attributed material hosted by a third party has weaker provenance than an original template or author-hosted publication. The technical design is a proposal and has not been implemented.

- **S1 — BBMA Mastery 2017**, text attributed to Gero Azrul, third-party transcription: https://www.academia.edu/76585590/Bbma_mastery
- **S2 — Road to FTT public channel**, worked multi-timeframe analysis and trading styles: https://t.me/s/road2ftt?before=2594
- **S3 — Road to FTT public channel**, timeframe selection: https://telegram.me/s/road2ftt?before=3433
- **S4 — Road to FTT public channel**, mapping, dominant setups and advanced-term mentions: https://telegram.me/s/road2ftt?before=2927
- **S5 — BBmastery Simplified public channel**, contextual educational material: https://t.me/s/bbsimplified
- **S6 — Road to FTT video channel**, further original demonstrations to inspect: https://www.youtube.com/roadtoftt

No independently verified strategy performance record is attached. Marketing examples or isolated winning trades must not be used as substitutes for this framework's validation study.

## 24. Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 30 October 2026 | Initial comprehensive research framework, explicit proposed baseline, unresolved-rule register and development handover |

