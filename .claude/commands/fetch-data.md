# /fetch-data — Fetch Historical Market Data

Download and store historical OHLCV candles for a given instrument and timeframe.

## Usage
```
/fetch-data <INSTRUMENT> <TIMEFRAME> [COUNT]
```

Examples:
```
/fetch-data EUR_USD H1
/fetch-data GBP_USD M15 2000
/fetch-data USD_JPY D 500
```

Supported timeframes: `M1 M5 M15 M30 H1 H4 D W`
Default count: 500 candles

## What this skill does

Uses the `market-data-analyst` agent to:

1. Connect to OANDA REST API using env vars (`OANDA_API_KEY`, `OANDA_ACCOUNT_ID`, `OANDA_ENV`)
2. Fetch the requested number of completed candles
3. Validate data quality (no gaps, no NaN, OHLC consistency)
4. Save to `data/history/<INSTRUMENT>/<TIMEFRAME>.csv` in UTC
5. Print a summary: row count, date range, any gaps found

## Output Files

```
data/history/EUR_USD/H1.csv
data/history/EUR_USD/M15.csv
```

CSV schema:
```
time,open,high,low,close,volume
2024-01-02 00:00:00+00:00,1.10512,1.10634,1.10489,1.10601,1234
```

## Notes

- Requires `OANDA_API_KEY` and `OANDA_ACCOUNT_ID` env vars set
- Uses `OANDA_ENV=practice` by default — practice account data is sufficient for backtesting
- OANDA API maximum per request: 5000 candles; large requests are automatically paginated
- Data is appended if the file already exists and the date range does not overlap
