# Agent tool server (runs inside Termux)

This tiny Node.js server (no npm packages needed — pure built-ins) gives
the Flutter app confined shell/file access on the phone. Run it alongside
9Router.

> **Naming note:** the environment variable is called `CLAUDE_AGENT_KEY`
> (not just `AGENT_KEY`) specifically to avoid colliding with other tools
> that also read a plain `AGENT_KEY` env var — for example Nous Research's
> Hermes Agent, if you also have that installed in the same Termux
> environment. Environment variables are global to your shell, so two
> unrelated tools using the same generic name will silently step on each
> other otherwise.

## Run it

```bash
# Pick a random key once and keep using the same one — the Flutter app's
# Settings screen needs the exact same value.
export CLAUDE_AGENT_KEY="$(head -c 24 /dev/urandom | base64)"
echo "Your key: $CLAUDE_AGENT_KEY"   # copy this into the app's Settings

node agent_server.js
```

By default it listens on `http://127.0.0.1:8765` (loopback only — not
reachable from other devices on your network), and confines all file
operations and shell commands to `~/agent_workspace` (created
automatically). Override either with environment variables before
starting it:

```bash
export AGENT_PORT=8765
export AGENT_WORKSPACE="$HOME/my_project"
```

## Keep it running

Same as 9Router — Termux can get suspended by Android in the background.
Run `termux-wake-lock` in the session, and consider running both 9Router
and this server under a process manager like `pm2` or in separate Termux
sessions (`tmux`/`screen`) so one crashing doesn't take down the other.

A simple way to run both at once:

```bash
# terminal/session 1
cd ~/9router && npm run start

# terminal/session 2 (e.g. a second Termux session)
export CLAUDE_AGENT_KEY="..."
cd ~/claude_flutter_app/termux_agent_server
node agent_server.js
```

## What it does NOT do

- It does not sandbox commands beyond confining their working directory —
  it trusts whatever command it's given to run. The Flutter app is
  responsible for asking you to confirm before sending any shell command;
  this server is intentionally simple/dumb on purpose so it's easy to
  audit (~150 lines, no dependencies).
- It only binds to `127.0.0.1`, so it isn't reachable from other devices on
  your Wi-Fi — only from processes on the same phone.
