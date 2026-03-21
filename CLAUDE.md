# CLAUDE.md — BotHub Codebase Guide

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
