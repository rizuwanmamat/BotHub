# /backtest-analyze — Analyze a Backtest Report

Parse and evaluate a MetaTrader Strategy Tester report or Python backtest output.

## Usage
```
/backtest-analyze <path/to/report>
/backtest-analyze               # looks for latest report in backtest/reports/
```

Supported input formats:
- MetaTrader Strategy Tester HTML export (`*.htm` or `*.html`)
- MetaTrader XML report (`*.xml`)
- Python backtest CSV trade log (`*.csv` with columns: entry_time, exit_time, direction, pnl)
- Plain text summary pasted directly into the prompt

## What this skill does

Uses the `backtest-analyst` agent to:

1. Parse all available metrics from the report
2. Evaluate each metric against project thresholds:
   - Profit factor ≥ 1.3 (target 1.5+)
   - Max drawdown ≤ 25% (target < 15%)
   - Total trades ≥ 100
   - Win rate context vs R:R ratio
   - Sharpe ratio ≥ 0.8
3. Check for overfitting red flags
4. Produce a structured report at `backtest/reports/<StrategyName>_<date>.md`
5. Give a verdict: PASS / CONDITIONAL PASS / FAIL
6. Recommend next steps (parameter adjustment, forward test, reject)

## Notes

- Always specify whether spread and commission were included in the backtest
- A PASS verdict does NOT authorise live trading — forward testing is always required next
