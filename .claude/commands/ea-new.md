# /ea-new — Scaffold a New Expert Advisor

Create a new Expert Advisor from the project template.

## Usage
```
/ea-new <StrategyName> [mql4|mql5]
```

## What this skill does

1. Ask the user for the strategy name and target platform (MQL4 or MQL5) if not provided
2. Ask for: primary instrument, timeframe, brief description of the logic
3. Use the `ea-developer` agent to generate:
   - `ea/<mqlversion>/Experts/<StrategyName>.mq4` or `.mq5`
   - Skeleton `OnInit`, `OnDeinit`, `OnTick` with new-bar guard
   - All mandatory `input` parameters (Magic, RiskPct, SL, TP)
   - Placeholder entry/exit logic with `// TODO` comments
4. Also create `strategy/specs/<StrategyName>.md` using the strategy spec template
5. Report the files created and next steps (fill in logic, compile in MetaEditor, backtest)

## Rules

- Default to MQL5 unless the user specifies MQL4 or their broker requires it
- Magic number must be unique — check existing EAs in `ea/` for used values
- Never fill in real entry logic unless the user has described it — use `// TODO` placeholders
- Remind the user to compile and test on a demo account first
