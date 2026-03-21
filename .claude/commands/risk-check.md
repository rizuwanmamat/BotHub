# /risk-check — Validate Risk Parameters Before Deployment

Run a full risk audit on an EA configuration or Python strategy settings.

## Usage
```
/risk-check <path/to/EA.mq5>
/risk-check <path/to/config/.env>
/risk-check               # audits all EAs and risk/manager.py
```

## What this skill does

Uses the `risk-validator` agent to:

1. Read the EA input parameters or Python config
2. Compute effective risk per trade at different account sizes ($1k, $5k, $10k, $100k)
3. Verify every hard limit from the risk rules table
4. Check that risk management code paths exist and are reachable
5. Produce a risk audit file at `risk/audits/<StrategyName>_audit.md`

## Verdict Levels

| Verdict | Meaning |
|---------|---------|
| APPROVED | All hard limits pass. Proceed to demo deployment. |
| CONDITIONAL | Minor issues found. Fix before demo deployment. |
| BLOCKED | Hard limit violation. Must fix before any deployment. |

## Hard Limits (any violation = BLOCKED)

- Risk per trade > 2% → BLOCKED
- No SL defined → BLOCKED
- Daily loss cap missing → BLOCKED
- Max drawdown halt missing → BLOCKED
- Fixed lot size (not balance-based) on live-capable config → BLOCKED

## Notes

- This check must be run and pass as APPROVED or CONDITIONAL before any demo or live deployment
- Re-run after every change to EA input parameters or risk/manager.py
