# /strategy-design — Research and Design a Trading Strategy

Produce a complete strategy specification document before any code is written.

## Usage
```
/strategy-design <brief description>
```

Examples:
```
/strategy-design MA crossover with RSI filter on EUR/USD H1
/strategy-design Bollinger Band breakout with ATR stop loss
/strategy-design London open breakout strategy
```

## What this skill does

Uses the `strategy-researcher` agent to:

1. Research the named indicators and their mechanics
2. Define precise, unambiguous entry and exit rules for both LONG and SHORT
3. Identify optimal instruments and timeframes
4. Identify market conditions where the strategy works and where it fails
5. Propose initial parameter ranges for backtesting (wide, not point-optimised)
6. Document known risks and weaknesses
7. Produce a spec file at `strategy/specs/<StrategyName>.md`

## Output

A complete strategy spec document following the project template including:
- Summary
- Market conditions (trending/ranging/breakout)
- Instruments & timeframes
- Indicator table with parameters and purpose
- Entry rules (long and short)
- Exit rules (SL, TP, trailing, time-based)
- Initial parameter ranges for optimisation
- Known risks & weaknesses
- References

## Next Steps After This Command

1. Review the spec and adjust entry/exit rules if needed
2. Run `/ea-new <StrategyName>` to scaffold the EA implementation
3. Implement logic in MetaEditor, compile and fix errors
4. Run backtest in MT5 Strategy Tester
5. Run `/backtest-analyze` on the report
6. Run `/risk-check` on the EA
7. Deploy to demo account for forward testing
