# CLAUDE.md — BotHub & Trading Bot Codebase Guide

## Project Overview

**BotHub** is a Telegram userbot framework built on [Telethon](https://github.com/LonamiWebs/Telethon) and the [Uniborg](https://github.com/uniborg-rs/uniborg) plugin architecture. It runs as a Telegram client (not a bot token), executing commands sent by the account owner. It supports 280+ plugins covering media processing, group administration, AI integrations, and utility commands.

**Tech Stack:**
- Python 3.7+ / AsyncIO
- Telethon (Telegram MTProto client)
- SQLAlchemy ORM (PostgreSQL or SQLite)
- MongoDB (pymongo)
- Redis (caching)
- Docker / Heroku deployment

---

## Repository Structure

```
BotHub/
├── stdborg.py                  # Main entry point
├── sample_config.py            # Configuration template (copy to config.py)
├── GenerateStringSession.py    # Interactive session generator
├── telesetup.py                # Telegram setup utility
├── requirements.txt            # Core dependencies
├── requirements-stdborg.txt    # Extended dependencies
├── Dockerfile                  # Alpine Linux container (40+ system packages)
├── Procfile                    # Heroku worker process
├── heroku.yml                  # Heroku build config
├── app.json                    # Heroku deploy button manifest
│
├── uniborg/                    # Core framework
│   ├── uniborg.py              # Custom TelegramClient subclass + plugin loader
│   ├── _core.py                # Built-in admin commands (.load, .unload, etc.)
│   ├── _inline_bot.py          # Inline query handler and help system
│   ├── util.py                 # admin_cmd(), progress(), humanbytes(), etc.
│   ├── storage.py              # Per-plugin JSON storage backend
│   ├── hacks.py                # ReverseList for plugin handler precedence
│   └── prettyjson.py           # JSON formatting utilities
│
├── userbot/                    # Shared userbot utilities
│   ├── helper_funcs/           # ids.py, misc.py, parser.py, sed.py, time.py, yt_dl.py
│   └── utils/                  # FastTelethon.py, custom.py, events.py, helpers.py,
│                               #   client.py, pluginManager.py, meval.py
│
├── stdplugins/                 # 281 plugin files (loaded at startup)
│   └── README.md               # Plugin development guide
│
├── dbplugins/                  # Plugins requiring database (loaded conditionally)
│   ├── antiflood.py
│   ├── blacklist.py
│   ├── filters.py
│   ├── locks.py
│   ├── warns.py
│   ├── welcome.py
│   └── ...
│
├── sql_helpers/                # SQLAlchemy models
│   ├── blacklist_sql.py
│   ├── filters_sql.py
│   ├── global_bans_sql.py
│   ├── warns_sql.py
│   ├── welcome_sql.py
│   └── ...                     # ~17 model files total
│
├── english/                    # Localization/string files
├── sessions/                   # Telegram session storage (gitignored)
└── MaterLang_Fonts/            # Font resources for image plugins
```

---

## Entry Point & Startup Flow

```
python3 -m stdborg [session_name]     # Local
HU_STRING_SESSION=... python3 -m stdborg  # Heroku/Docker

stdborg.py
  ├── Load config (ENV vars or config.py)
  ├── Create Uniborg(TelegramClient) instance
  │   ├── Load uniborg/_core.py  (plugin management commands)
  │   ├── Load uniborg/_inline_bot.py  (help system)
  │   ├── Glob stdplugins/*.py  (281 plugins, filtered by LOAD/NO_LOAD)
  │   └── Connect MongoDB if MONGO_URI is set
  └── borg.run_until_disconnected()
```

**Run modes:**
- **Local:** `python3 -m stdborg <session_name>` — uses `sessions/<session_name>.session`
- **Heroku/Docker:** Set `HU_STRING_SESSION` env var — uses StringSession

---

## Configuration

Copy `sample_config.py` to `config.py` and fill in the values. The config is accessed everywhere via:

```python
from sample_config import Config
# or, if using a local config:
from config import Development as Config
```

**Required variables:**
| Variable | Description |
|---|---|
| `APP_ID` | Telegram API ID from my.telegram.org |
| `API_HASH` | Telegram API hash from my.telegram.org |
| `HU_STRING_SESSION` | StringSession (for Heroku/Docker) |

**Optional but common:**
| Variable | Description |
|---|---|
| `DB_URI` | SQLAlchemy DB URL (PostgreSQL or SQLite) |
| `MONGO_URI` | MongoDB connection string |
| `HEROKU_API_KEY` | Heroku integration |
| `HEROKU_APP_NAME` | Heroku app name |
| `UPSTREAM_REPO_URL` | Plugin update source |
| `NO_LOAD` | Comma-separated plugins to disable |
| `LOAD` | Comma-separated plugins to enable exclusively |
| `SUDO_USERS` | Space-separated Telegram user IDs for sudo access |
| `COMMAND_HAND_LER` | Command prefix, default `.` |
| `PRIVATE_GROUP_BOT_API_ID` | Log group/channel ID |

All config values can be overridden by environment variables (same name).

---

## Plugin Development

### Plugin Anatomy

Plugins are single `.py` files in `stdplugins/`. They are loaded as modules with these globals injected automatically:

| Global | Type | Description |
|---|---|---|
| `borg` | `Uniborg` | The Telegram client instance |
| `logger` | `logging.Logger` | Plugin-scoped logger |
| `storage` | `Storage` | Per-plugin JSON storage |
| `Config` | `class` | Configuration object |
| `tgbot` | `TelegramClient` | Inline bot client (if configured) |
| `mongo_client` | `MongoClient` | MongoDB client (if configured) |

### Minimal Plugin Example

```python
# stdplugins/myplugin.py

@borg.on(admin_cmd("hello"))
async def hello_handler(event):
    if event.fwd_from:
        return  # Skip forwarded messages
    await event.edit("Hello, world!")
```

### admin_cmd() Decorator

`admin_cmd()` is defined in `uniborg/util.py`. It:
- Prepends `Config.COMMAND_HAND_LER` (default `.`) to the pattern
- Filters to outgoing messages only (the account owner)
- Handles `SUDO_USERS` if `allow_sudo=True`
- Skips chats in `UB_BLACK_LIST_CHAT`

```python
from uniborg.util import admin_cmd

@borg.on(admin_cmd(pattern=r"cmd(?:\s+(.+))?", allow_sudo=False))
async def my_cmd(event):
    arg = event.pattern_match.group(1)
    await event.edit(f"Arg: {arg}")
```

### Docstring Convention

Plugins use docstrings for the built-in `.helpme` and `.syntax` commands:

```python
@borg.on(admin_cmd("mycommand"))
async def handler(event):
    """
    .mycommand <args>
    Does something useful.
    """
    pass
```

### Plugin Storage

Each plugin gets isolated JSON storage in `data/<username>/<pluginname>/data.json`:

```python
# Write
storage.mykey = "value"

# Read
value = storage.mykey  # None if not set

# Bulk operations (atomic)
with storage.bulk_save():
    storage.key1 = "a"
    storage.key2 = "b"
```

### Database Access (dbplugins)

Plugins in `dbplugins/` can use SQLAlchemy models from `sql_helpers/`:

```python
from sql_helpers.warns_sql import add_warn, get_warns
from sql_helpers import SESSION

# Use the shared session
result = SESSION.query(MyModel).filter_by(chat_id=str(chat_id)).first()
SESSION.add(new_record)
SESSION.commit()
```

---

## Key Utilities (`uniborg/util.py`)

```python
from uniborg.util import (
    admin_cmd,      # Command decorator
    humanbytes,     # Format bytes → "1.5 MB"
    time_formatter, # ms → "1d 2h 3m 4s"
    progress,       # Upload/download progress callback
    is_read,        # Check if message is read
)
```

---

## Coding Conventions

### Async Patterns
All event handlers must be `async def`. Use `await` for all Telegram API calls:

```python
async def handler(event):
    await event.edit("Processing...")
    # ... do work ...
    await event.edit("Done!")
```

### Forwarded Message Guard
Always add this guard at the start of handlers to avoid reacting to forwarded messages:

```python
if event.fwd_from:
    return
```

### Pattern Matching
Use named or positional groups with `event.pattern_match`:

```python
@borg.on(admin_cmd(r"cmd(?:\s+(.+))?"))
async def handler(event):
    arg = event.pattern_match.group(1)
    if not arg:
        await event.edit("Usage: .cmd <text>")
        return
```

### Progress Feedback
For long-running operations (uploads, downloads), use `progress()`:

```python
from uniborg.util import progress

await borg.send_file(
    event.chat_id,
    file,
    progress_callback=lambda d, t: asyncio.ensure_future(
        progress(d, t, event, time.time(), "Uploading...")
    )
)
```

### Error Handling
Wrap external API calls in try/except and report errors gracefully:

```python
try:
    result = await some_api_call()
    await event.edit(f"Result: {result}")
except Exception as e:
    logger.exception("API call failed")
    await event.edit(f"Error: `{e}`")
```

### Logging
Use the injected `logger` (not `print`):

```python
logger.info("Plugin loaded")
logger.warning("Something unexpected")
logger.exception("Error details")  # Includes traceback
```

---

## Plugin Loading Control

Control which plugins load via config:

```python
# Disable specific plugins
NO_LOAD = ["pmpermit", "autores", "left", "hand"]

# Enable ONLY these plugins (overrides NO_LOAD)
LOAD = ["ping", "alive", "info"]
```

At runtime (via `.load` / `.unload` commands built into `_core.py`):
```
.load myplugin      # Load plugin from stdplugins/myplugin.py
.unload myplugin    # Unload a running plugin
.send plugin        # Send a plugin file
.install plugin     # Install from message attachment
```

---

## Deployment

### Local (Linux/macOS)

```bash
# 1. Clone and configure
git clone <repo> && cd BotHub
cp sample_config.py config.py
# Edit config.py with your credentials

# 2. Generate session
python3 GenerateStringSession.py

# 3. Install dependencies
pip3 install -r requirements.txt
pip3 install -r requirements-stdborg.txt

# 4. Run
python3 -m stdborg <session_name>
```

### Docker

```bash
docker build -t bothub .
docker run -e HU_STRING_SESSION=... -e APP_ID=... -e API_HASH=... bothub
```

### Heroku

- Use the **Deploy to Heroku** button in `app.json`
- Set all required environment variables in Heroku dashboard
- Worker dyno runs `python3 -m stdborg`

---

## Built-in Commands (from `_core.py`)

| Command | Description |
|---|---|
| `.load <plugin>` | Load a plugin by name |
| `.unload <plugin>` | Unload a running plugin |
| `.send plugin` | Send current plugin file |
| `.install plugin` | Install plugin from attachment |
| `.helpme <plugin>` | Show plugin help (uses docstrings) |
| `.syntax <plugin>` | Show plugin syntax |

---

## Security Considerations

- **Never commit** `config.py`, session files (`sessions/`), or `.env` files
- `SUDO_USERS` grants nearly full bot control — be careful who you add
- The `.exec` command (if loaded) can execute arbitrary shell commands; document notes `rm -rf /*` as a risk
- API keys in `sample_config.py` are placeholders only; rotate any accidentally exposed keys
- Session strings in `HU_STRING_SESSION` must be kept secret — they grant full Telegram account access

---

## Common Patterns Reference

### Send a file with caption
```python
await borg.send_file(event.chat_id, "/path/to/file", caption="Caption")
```

### Edit vs Reply
```python
await event.edit("text")          # Edit the command message
await event.reply("text")         # Reply to the command message
await event.respond("text")       # Send new message in same chat
```

### Get command arguments
```python
@borg.on(admin_cmd(r"cmd(?:\s+(.+))?"))
async def handler(event):
    text = event.pattern_match.group(1)
    if not text and event.reply_to_msg_id:
        reply = await event.get_reply_message()
        text = reply.text
```

### Access sender info
```python
sender = await event.get_sender()
chat = await event.get_chat()
```

### Delete message after action
```python
await asyncio.sleep(5)
await event.delete()
```

---

## Dependency Notes

- `requirements.txt` — minimal runtime deps (install first)
- `requirements-stdborg.txt` — full feature set including media, AI, social APIs
- The Dockerfile uses Alpine Linux and installs system packages including `ffmpeg`, `chromium`, `imagemagick`, `aria2`, and PostgreSQL client
- `runtime.txt` pins the Python version for Heroku

---

## No Tests

There is no automated test suite. Testing is done manually via Telegram commands. The `.gitlab-ci.yml` is a placeholder. When contributing:
- Test commands manually in a private Telegram chat
- Check `.helpme` and `.syntax` output matches your docstrings
- Verify `NO_LOAD` and `LOAD` filtering works if your plugin is optional

---

---

# AI Agents & Skills for Trading EA Development

This section documents the sub-agents and slash command skills defined in
`.claude/agents/` and `.claude/commands/`. They are purpose-built for the
trading bot and Expert Advisor development workflow.

---

## Sub-Agents (`.claude/agents/`)

Sub-agents are invoked automatically by Claude when the task matches their
description, or explicitly via the Agent tool. Each agent has a focused role
and a restricted tool set.

| Agent | File | Invoke When |
|-------|------|-------------|
| `ea-developer` | `ea-developer.md` | Writing, modifying, or fixing MQL4/MQL5 EA and indicator files |
| `strategy-researcher` | `strategy-researcher.md` | Designing a new strategy, researching indicators, producing a spec doc |
| `backtest-analyst` | `backtest-analyst.md` | Interpreting MT4/MT5 Strategy Tester reports or Python backtest output |
| `risk-validator` | `risk-validator.md` | Auditing EA inputs or Python config against risk rules before deployment |
| `broker-api-developer` | `broker-api-developer.md` | Building or debugging OANDA / IC Markets cTrader Python client code |
| `market-data-analyst` | `market-data-analyst.md` | Fetching historical candles, computing indicators, preparing backtest data |

### Agent Responsibilities at a Glance

```
strategy-researcher   →  defines WHAT to build (spec doc)
        ↓
ea-developer          →  builds the MQL EA or Python strategy
market-data-analyst   →  fetches data for backtesting
        ↓
backtest-analyst      →  evaluates the backtest results
        ↓
risk-validator        →  approves risk parameters before deployment
        ↓
broker-api-developer  →  connects to live/demo broker for execution
```

---

## Slash Command Skills (`.claude/commands/`)

Skills are slash commands invoked by the user to trigger a multi-step workflow.

| Command | File | Purpose |
|---------|------|---------|
| `/ea-new` | `ea-new.md` | Scaffold a new EA from template (MQL4 or MQL5) |
| `/ea-review` | `ea-review.md` | Code quality + risk audit on one or all EAs |
| `/strategy-design` | `strategy-design.md` | Research and produce a strategy spec document |
| `/backtest-analyze` | `backtest-analyze.md` | Parse and evaluate a backtest report |
| `/risk-check` | `risk-check.md` | Validate risk parameters before any deployment |
| `/fetch-data` | `fetch-data.md` | Download historical OHLCV data from OANDA |

### Typical Development Workflow Using Skills

```
1.  /strategy-design "MA crossover with RSI filter on EUR/USD H1"
        → produces strategy/specs/MACrossoverRSI.md

2.  /ea-new MACrossoverRSI mql5
        → produces ea/mql5/Experts/MACrossoverRSI.mq5

3.  [developer implements logic in MetaEditor, compiles]

4.  /fetch-data EUR_USD H1 2000
        → downloads data to data/history/EUR_USD/H1.csv

5.  [run backtest in MT5 Strategy Tester, export HTML report]

6.  /backtest-analyze backtest/reports/MACrossoverRSI_20250101.htm
        → produces backtest/reports/MACrossoverRSI_20250101.md

7.  /risk-check ea/mql5/Experts/MACrossoverRSI.mq5
        → produces risk/audits/MACrossoverRSI_audit.md

8.  /ea-review ea/mql5/Experts/MACrossoverRSI.mq5
        → final code quality + risk review

9.  [if all PASS → deploy to MT5 demo for forward testing]
```

---

---

# Trading Bot & Expert Advisor (EA) Guide

This section documents the standalone trading bot project — separate from the Telegram userbot above. It targets **MetaTrader 4/5 Expert Advisors (MQL)** and **Forex broker REST APIs** (OANDA, IC Markets).

---

## Project Structure (Trading Bot)

```
trading/
├── ea/                         # MetaTrader Expert Advisors (MQL4/MQL5)
│   ├── mql4/
│   │   ├── Experts/            # EA source files (.mq4)
│   │   ├── Indicators/         # Custom indicator files (.mq4)
│   │   └── Include/            # Shared header files (.mqh)
│   └── mql5/
│       ├── Experts/            # EA source files (.mq5)
│       ├── Indicators/         # Custom indicators (.mq5)
│       └── Include/            # Shared headers (.mqh)
│
├── broker/                     # Python broker API clients
│   ├── oanda/
│   │   ├── client.py           # OANDA REST v20 wrapper
│   │   ├── stream.py           # Pricing stream (WebSocket)
│   │   └── orders.py           # Order management
│   └── icmarkets/
│       ├── client.py           # IC Markets cTrader / FIX API wrapper
│       └── orders.py
│
├── strategy/                   # Strategy logic (Python)
│   ├── base.py                 # Abstract Strategy class
│   ├── indicators.py           # TA indicators (MA, RSI, MACD, ATR, etc.)
│   └── <strategy_name>.py      # One file per strategy
│
├── risk/
│   ├── manager.py              # Position sizing, drawdown limits
│   └── rules.py                # Risk rules (max lots, daily loss cap, etc.)
│
├── data/
│   ├── feed.py                 # Live price feed handler
│   ├── history.py              # Historical OHLCV fetching
│   └── store.py                # Local tick/candle storage (SQLite/CSV)
│
├── backtest/
│   ├── engine.py               # Event-driven backtesting loop
│   ├── report.py               # P&L, Sharpe, drawdown reporting
│   └── optimizer.py            # Parameter optimization
│
├── config/
│   ├── settings.py             # Central config (loaded from .env)
│   └── .env.example            # Environment variable template
│
├── tests/
│   ├── test_strategy.py
│   ├── test_risk.py
│   └── test_orders.py
│
├── main.py                     # Entry point — live trading runner
├── requirements.txt            # Python dependencies
└── README.md
```

---

## MetaTrader Expert Advisor (MQL) Development

### MQL4 vs MQL5

| Feature | MQL4 | MQL5 |
|---|---|---|
| Platform | MetaTrader 4 | MetaTrader 5 |
| Language style | C-like, simpler | C++ OOP, stricter |
| Brokers | Most retail forex brokers | Growing adoption |
| Backtesting | Single-threaded | Multi-threaded, faster |
| File extension | `.mq4` / `.ex4` | `.mq5` / `.ex5` |

Prefer **MQL5** for new EAs unless the broker only supports MT4.

### EA File Structure (MQL5 example)

```mql5
//+------------------------------------------------------------------+
//| MyStrategy.mq5                                                   |
//+------------------------------------------------------------------+
#property copyright "BotHub Trading"
#property version   "1.00"
#property strict

// Input parameters (visible in MT5 Strategy Tester & Attach dialog)
input double LotSize    = 0.01;
input int    MAPeriod   = 20;
input double StopLoss   = 50.0;   // Points
input double TakeProfit = 100.0;  // Points

// Global handles
int maHandle;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit() {
    maHandle = iMA(_Symbol, PERIOD_CURRENT, MAPeriod, 0, MODE_SMA, PRICE_CLOSE);
    if (maHandle == INVALID_HANDLE) return INIT_FAILED;
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    IndicatorRelease(maHandle);
}

//+------------------------------------------------------------------+
//| Called on every new tick                                         |
//+------------------------------------------------------------------+
void OnTick() {
    // Only act on new bar open
    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
    if (currentBar == lastBar) return;
    lastBar = currentBar;

    // Get indicator value
    double maBuffer[];
    ArraySetAsSeries(maBuffer, true);
    CopyBuffer(maHandle, 0, 0, 3, maBuffer);

    double close = iClose(_Symbol, PERIOD_CURRENT, 1);
    double ma    = maBuffer[1];

    // Entry logic
    if (close > ma && PositionsTotal() == 0) {
        OpenBuy();
    } else if (close < ma && PositionsTotal() == 0) {
        OpenSell();
    }
}

//+------------------------------------------------------------------+
//| Open a BUY market order                                          |
//+------------------------------------------------------------------+
void OpenBuy() {
    MqlTradeRequest req = {};
    MqlTradeResult  res = {};
    req.action    = TRADE_ACTION_DEAL;
    req.symbol    = _Symbol;
    req.volume    = LotSize;
    req.type      = ORDER_TYPE_BUY;
    req.price     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    req.sl        = req.price - StopLoss  * _Point;
    req.tp        = req.price + TakeProfit * _Point;
    req.deviation = 10;
    req.magic     = 123456;
    req.comment   = "MyStrategy BUY";
    OrderSend(req, res);
}
```

### EA Coding Conventions (MQL)

- **Always use `input` for parameters** — never hardcode values that a user might want to change
- **Use magic numbers** — set a unique `magic` integer per EA to identify its orders
- **Check `PositionsTotal()` / `OrdersTotal()`** before opening new positions to avoid duplicates
- **New-bar guard** — use a `static datetime lastBar` check inside `OnTick()` to run logic once per candle, not on every tick
- **Avoid blocking calls** in `OnTick()` — no `Sleep()`, no heavy loops
- **Handle errors** — check `res.retcode` after `OrderSend()`:
  ```mql5
  if (res.retcode != TRADE_RETCODE_DONE) {
      Print("OrderSend failed: ", res.retcode, " ", res.comment);
  }
  ```
- **Use `_Point` and `_Digits`** — never hardcode pip values; they vary by instrument
- **Normalize prices** — `NormalizeDouble(price, _Digits)` before using in orders
- **Stop Loss / Take Profit** — always set; never trade without a defined exit
- **Separate concerns** — put indicator logic in `/Include/` headers, keep EA files focused on entry/exit logic

### EA Testing Workflow (MetaTrader Strategy Tester)

1. Compile the `.mq5` file in MetaEditor (F7)
2. Open Strategy Tester (Ctrl+R in MT5)
3. Select EA, symbol, timeframe, date range
4. Run **Visual Mode** first to spot obvious bugs
5. Run **Every Tick** mode for accurate backtest
6. Check: total trades, win rate, profit factor (>1.5 target), max drawdown (<20% target)
7. Use **Optimization** tab to find parameter ranges — avoid overfitting

---

## Forex Broker API (Python)

### OANDA REST v20

OANDA provides a fully documented REST API for live and paper trading.

**Authentication:**
```python
# config/.env
OANDA_API_KEY=your_api_key_here
OANDA_ACCOUNT_ID=001-001-XXXXXXX-001
OANDA_ENV=practice   # or "live"
```

**Base client (`broker/oanda/client.py`):**
```python
import os
import requests

BASE_URLS = {
    "practice": "https://api-fxpractice.oanda.com",
    "live":     "https://api-fxtrade.oanda.com",
}

class OandaClient:
    def __init__(self):
        self.api_key    = os.environ["OANDA_API_KEY"]
        self.account_id = os.environ["OANDA_ACCOUNT_ID"]
        self.base_url   = BASE_URLS[os.environ.get("OANDA_ENV", "practice")]
        self.session    = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type":  "application/json",
        })

    def get_account(self):
        r = self.session.get(f"{self.base_url}/v3/accounts/{self.account_id}")
        r.raise_for_status()
        return r.json()

    def get_price(self, instrument: str) -> dict:
        r = self.session.get(
            f"{self.base_url}/v3/accounts/{self.account_id}/pricing",
            params={"instruments": instrument}
        )
        r.raise_for_status()
        return r.json()["prices"][0]

    def place_market_order(self, instrument: str, units: int,
                           sl_price: float = None, tp_price: float = None) -> dict:
        order = {
            "order": {
                "type":       "MARKET",
                "instrument": instrument,
                "units":      str(units),  # positive = buy, negative = sell
            }
        }
        if sl_price:
            order["order"]["stopLossOnFill"] = {"price": f"{sl_price:.5f}"}
        if tp_price:
            order["order"]["takeProfitOnFill"] = {"price": f"{tp_price:.5f}"}

        r = self.session.post(
            f"{self.base_url}/v3/accounts/{self.account_id}/orders",
            json=order
        )
        r.raise_for_status()
        return r.json()

    def close_trade(self, trade_id: str) -> dict:
        r = self.session.put(
            f"{self.base_url}/v3/accounts/{self.account_id}/trades/{trade_id}/close"
        )
        r.raise_for_status()
        return r.json()
```

**Live price streaming:**
```python
# broker/oanda/stream.py
import sseclient, requests, os, json

def stream_prices(instruments: list, callback):
    url = f"https://stream-fxpractice.oanda.com/v3/accounts/{os.environ['OANDA_ACCOUNT_ID']}/pricing/stream"
    headers = {"Authorization": f"Bearer {os.environ['OANDA_API_KEY']}"}
    params  = {"instruments": ",".join(instruments)}
    r = requests.get(url, headers=headers, params=params, stream=True)
    for event in sseclient.SSEClient(r).events():
        tick = json.loads(event.data)
        if tick.get("type") == "PRICE":
            callback(tick)
```

### IC Markets (cTrader Open API)

IC Markets supports cTrader's Open API (protobuf-based WebSocket):

```
pip install ctrader-open-api
```

Key concepts:
- **Application auth** → client credentials (clientId, clientSecret)
- **Account auth** → access token per account
- **Spots** → subscribe to symbol price updates
- **New order** → `ProtoOANewOrderReq` message

Refer to the [cTrader Open API docs](https://help.ctrader.com/open-api/) for full message reference. Use the official Python sample as a starting point.

---

## Strategy Development

### Abstract Base Class

```python
# strategy/base.py
from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum

class Signal(Enum):
    BUY  = "BUY"
    SELL = "SELL"
    FLAT = "FLAT"

@dataclass
class Bar:
    time:   float
    open:   float
    high:   float
    low:    float
    close:  float
    volume: float

class Strategy(ABC):
    def __init__(self, params: dict):
        self.params = params

    @abstractmethod
    def on_bar(self, bars: list[Bar]) -> Signal:
        """Called on each new completed candle. Return a Signal."""
        ...

    @abstractmethod
    def name(self) -> str:
        ...
```

### Example Strategy

```python
# strategy/ma_crossover.py
from .base import Strategy, Signal, Bar

class MACrossover(Strategy):
    def name(self): return "MA Crossover"

    def on_bar(self, bars: list[Bar]) -> Signal:
        fast = self.params["fast_period"]
        slow = self.params["slow_period"]
        if len(bars) < slow:
            return Signal.FLAT
        fast_ma = sum(b.close for b in bars[-fast:]) / fast
        slow_ma = sum(b.close for b in bars[-slow:]) / slow
        if fast_ma > slow_ma:
            return Signal.BUY
        elif fast_ma < slow_ma:
            return Signal.SELL
        return Signal.FLAT
```

### Coding Conventions (Python Trading Bot)

- **Never use `time.sleep()` in live loops** — use async/await or event-driven patterns
- **All prices are floats** — use `round(price, instrument_digits)` before order submission
- **Units vs lots** — OANDA uses integer units (1 unit = 1 base currency); MT5 uses lots (0.01 minimum for most brokers)
- **Always define SL/TP at order time** — never place a naked order in live trading
- **Paper trade first** — use `OANDA_ENV=practice` or MT5 demo account; never test on live funds
- **Config via env vars** — no API keys or account IDs in source files
- **Log every order** — write to a structured log file with timestamp, instrument, direction, size, price, SL, TP
- **Idempotent order logic** — check open positions before placing new orders; avoid doubling up
- **Separate signal from execution** — strategy returns a `Signal`; a separate executor handles broker calls
- **Backtest before live** — every strategy must have a backtest run before being deployed live

---

## Risk Management Rules

Always enforce these in `risk/manager.py` before any order is placed:

| Rule | Default | Notes |
|---|---|---|
| Max lot size | 2% of account balance | Calculated per trade |
| Max open trades | 3 | Per instrument, per direction |
| Daily loss limit | 5% of account balance | Pause trading if hit |
| Max drawdown | 15% of peak balance | Stop all trading, alert |
| Min SL distance | 10 pips | Reject orders with tighter SL |
| Spread check | < 3 pips for majors | Skip trade during high spread |

```python
# risk/manager.py
class RiskManager:
    def __init__(self, account_balance: float, params: dict):
        self.balance = account_balance
        self.params  = params

    def lot_size(self, sl_pips: float, pip_value: float) -> float:
        risk_amount = self.balance * self.params["risk_pct"]
        return round(risk_amount / (sl_pips * pip_value), 2)

    def can_trade(self, open_positions: int, daily_loss: float) -> bool:
        if open_positions >= self.params["max_trades"]:
            return False
        if daily_loss >= self.balance * self.params["daily_loss_limit"]:
            return False
        return True
```

---

## Backtesting

The backtest engine (`backtest/engine.py`) should be event-driven — mirroring how the live system works:

1. Feed historical OHLCV bars one at a time to `strategy.on_bar()`
2. On a signal, call `risk.manager.can_trade()` then simulate order fill at next bar open
3. Track open trades, apply SL/TP hits bar by bar
4. Produce a trade log and summary report

**Key metrics to report:**
- Net profit / loss
- Win rate (%)
- Profit factor (gross profit / gross loss) — target > 1.5
- Max drawdown (%) — target < 20%
- Sharpe ratio — target > 1.0
- Average trade duration
- Total trades (minimum ~100 for statistical significance)

---

## Environment Variables (Trading Bot)

```bash
# config/.env.example

# OANDA
OANDA_API_KEY=
OANDA_ACCOUNT_ID=
OANDA_ENV=practice          # practice | live

# IC Markets / cTrader
CTRADER_CLIENT_ID=
CTRADER_CLIENT_SECRET=
CTRADER_ACCESS_TOKEN=
CTRADER_ACCOUNT_ID=
CTRADER_ENV=demo            # demo | live

# Risk settings
RISK_PCT=0.02               # 2% per trade
MAX_OPEN_TRADES=3
DAILY_LOSS_LIMIT=0.05       # 5% of balance

# Logging
LOG_LEVEL=INFO
LOG_FILE=logs/trading.log
```

---

## Dependencies (Trading Bot)

```
# requirements.txt

# Broker APIs
requests>=2.31
sseclient-py>=1.8           # OANDA price streaming
ctrader-open-api>=2.0       # IC Markets cTrader

# Technical analysis
pandas>=2.0
numpy>=1.26
ta>=0.11                    # TA-Lib wrapper (RSI, MACD, BB, ATR, etc.)

# Backtesting
vectorbt>=0.26              # Fast vectorized backtest (optional)

# Config
python-dotenv>=1.0

# Testing
pytest>=8.0
pytest-asyncio>=0.23
```

> **Note:** For MT4/MT5 EA development, MetaEditor (bundled with the MetaTrader terminal) is the only required tool — no extra Python dependencies.

---

## File Naming & Organisation Conventions

| Context | Convention | Example |
|---|---|---|
| MQL EA files | PascalCase | `MACrossover.mq5` |
| MQL indicator files | PascalCase | `SuperTrend.mq5` |
| MQL include/header | PascalCase | `RiskManager.mqh` |
| Python modules | snake_case | `ma_crossover.py` |
| Python classes | PascalCase | `class MACrossover` |
| Config keys | UPPER_SNAKE | `OANDA_API_KEY` |
| Trade log entries | ISO 8601 timestamps | `2025-01-15T09:30:00Z` |

---

## Security (Trading Bot)

- **Never commit `.env`** files or any file containing API keys or account IDs
- **Use `practice`/`demo` accounts exclusively** until a strategy has a verified backtest + forward test period
- **Rate limits** — OANDA REST allows 100 requests/second; IC Markets cTrader is event-driven (no polling)
- **IP whitelisting** — enable it in your broker dashboard if supported
- **Revoke API keys immediately** if a repository is accidentally made public
