# Claude-style Chat (Flutter + 9Router)

A mobile chat app styled after Claude's own app — warm cream background,
terracotta accent, no-chrome assistant text, rounded everything — that talks
to a locally running **9Router** instance over its OpenAI-compatible API.

## What's new in this round

- **Fixed: attachment strip taking over the screen.** Every attachment
  kind (photos, videos, code files — even a zip with 50 files) now
  renders as one fixed-height (56px), horizontally scrolling strip. No
  matter how many files are attached, it can never grow to cover the send
  button or the rest of the screen.
- **Fixed: attached text/code files flooding the message.** Previously, a
  `.py` file (or a zip's contents) got folded directly into the visible
  message text as a giant fenced code block. Now `ChatMessage` keeps the
  attached file content separate from what's displayed — the bubble shows
  a small chip per file (tap it to view the full content in a sheet), while
  the full content is still folded in only for what's actually sent to the
  model (`ChatMessage._effectiveTextForApi`).
- **Video attachments**: the attach sheet now has "Choose video" and
  "Record video", sent as `video_url` content parts — the same pattern as
  images, extended to video. Support depends entirely on the model/router;
  some backends accept it, some will ignore or reject it. Capped at 15MB
  (after picking) since base64 video is heavy; camera recording is capped
  at 30 seconds, but gallery selection isn't (image_picker limitation), so
  oversized gallery videos are rejected with a clear message after picking
  rather than silently sent.
- **Collapsible, searchable model list** (Settings): collapsed by default
  showing just the current model; expanding reveals a search field and a
  height-bounded, virtualized list — stays usable whether 9Router reports
  5 models or 500.

- **Real web search**: `web_search` now scrapes DuckDuckGo's HTML results
  page (`html.duckduckgo.com/html/`) instead of the old Instant Answer API,
  which only ever answered a narrow set of curated queries. This returns
  actual result titles/snippets/links for ordinary searches. It's
  markup-scraping, not an official API, so if DuckDuckGo changes their
  HTML this is the one function to fix (`ToolService._webSearch`).
- **Shell confirmation is now optional**: **Settings → Coding tools → "Ask
  before running shell commands"**. Default is on (a dialog appears before
  every `run_shell` call); turn it off if the prompts are too tedious for
  your own trusted workflow — commands then run immediately.
- **Edit & resend**: tap the pencil icon under any of your messages to
  load it back into the input box; sending discards that message and
  everything after it, then sends the edited version as a fresh turn.
- **Regenerate / retry**: tap the refresh icon under the assistant's last
  reply to ask again with the same history — also doubles as the "retry"
  action when a reply failed.
- **Search chats**: a search field at the top of the conversation drawer
  filters by title or by message content.
- **Export / compact** (three-dot menu in the chat's app bar):
  - **Export as Markdown** — shares the current chat as readable text via
    the system share sheet.
  - **Compact this chat** — summarizes everything except the last few
    messages into one note (costs one model call), shrinking what gets
    resent on every future turn.
- **Backup & restore** (Settings): **Export all** writes every
  conversation to a JSON file and opens the share sheet (send it to
  yourself, save it to Drive, etc.); **Import** reads that file back in,
  merged alongside whatever's already there.
- **Context-length safety net**: before sending, `ChatProvider` estimates
  the size of the conversation and silently drops the oldest messages
  (keeping the system prompt) if it's getting too large for a typical
  context window, rather than letting a very long chat fail outright.

## What's included

- `lib/theme/app_theme.dart` — the full color palette (light + dark) and
  shared corner-radius/typography rules.
- `lib/models/` — `ChatMessage` (now with `ToolCall` support), `Conversation`.
- `lib/services/router_api_service.dart` — talks to 9Router:
  - `GET  {baseUrl}/models` to list models
  - `POST {baseUrl}/chat/completions` with `"stream": true` and OpenAI-style
    `"tools"`, parsed as SSE (`data: {...}` lines, `[DONE]` terminator),
    accumulating both text deltas and streamed `tool_calls` deltas.
- `lib/services/tool_service.dart` — the tool registry: **calculator**,
  **web_search** (DuckDuckGo Instant Answer API, no key needed), and
  **save_memory**. Each tool declares its own JSON-schema and a status
  label shown in the UI while it runs.
- `lib/services/expression_evaluator.dart` — a small dependency-free
  arithmetic parser backing the calculator tool.
- `lib/services/memory_service.dart` — a flat list of short remembered
  facts, persisted locally, folded into every system prompt.
- `lib/services/storage_service.dart` — local persistence (SharedPreferences)
  for conversations and settings, including the system prompt.
- `lib/providers/settings_provider.dart` — connection config, model list,
  editable **system prompt** (supports `{{date}}`/`{{time}}` placeholders),
  and a tools on/off switch.
- `lib/providers/chat_provider.dart` — conversations, streaming send/cancel,
  and the **tool-calling loop**: sends the request, and if the model asks
  for tools instead of answering, runs them locally and feeds the results
  back in (up to 5 rounds) before finalizing the answer.
- `lib/screens/home_screen.dart` — chat screen with empty-state suggestions,
  streaming bubbles, model picker in the app bar.
- `lib/screens/settings_screen.dart` — connection settings, model picker,
  tools toggle, system prompt editor, memory fact list (add/remove), theme.
- `lib/widgets/chat_bubble.dart` — markdown rendering with **code blocks
  broken out into their own card with a copy button**, a status chip while
  a tool is running (e.g. "Searching the web for…"), and a soft fade-in.
- `lib/widgets/chat_input_bar.dart` — input bar with light haptic feedback
  on send, and a send/stop button.
- `lib/widgets/` — conversation drawer (sidebar), model selector sheet.

## How tool calling works here

1. If **Settings → Tools** is on, every request includes the tool schemas
   from `ToolService.apiSchemas`.
2. If the model's streamed response includes `tool_calls` instead of (or
   before) a final answer, `ChatProvider` shows a small status chip
   ("Calculating…", "Searching the web for…"), runs the matching
   `ToolDefinition.execute`, and appends the JSON result as a `role: "tool"`
   message.
3. It sends the conversation again with that tool result included, and
   repeats (up to 5 rounds) until the model answers with plain text.
4. Tool call/result turns are **not** shown in the chat or saved to
   history — only the user's message and the final answer are, keeping the
   visible conversation clean. This does mean the model won't remember
   *which* tool it used in an older turn if you ask about it later — that's
   an intentional simplicity trade-off, not a bug.

To add your own tool: add a new `ToolDefinition` to the `tools` list in
`tool_service.dart` with a JSON-schema `parameters` block and an `execute`
function — no changes needed anywhere else.

## Coding tools (run_shell, read_file, write_file, list_dir)

These are **off by default** — turn them on in **Settings → Coding tools**.
Unlike the app itself, they reach a real shell and file system on your
phone, so they're kept separate and opt-in.

Because the Flutter app is its own sandboxed Android app, it can't execute
shell commands directly (`dart:io`'s `Process` isn't available on
Android/iOS). So these tools work by calling a tiny companion server —
**`termux_agent_server/agent_server.js`** — that you run inside Termux
alongside 9Router. It's plain Node.js with zero npm dependencies (~150
lines, easy to read end to end) and:

- confines all file operations and shell commands to one workspace folder
  (`~/agent_workspace` by default), rejecting any path that tries to
  escape it
- only listens on `127.0.0.1` (not reachable from other devices)
- requires a shared secret (`CLAUDE_AGENT_KEY`) on every request

**Every `run_shell` call asks you to approve it first** — a dialog pops up
in the app showing the exact command before anything runs; `read_file`,
`write_file`, and `list_dir` run without a prompt since they're confined to
the workspace folder.

Setup:

```bash
# in Termux, alongside 9Router
export CLAUDE_AGENT_KEY="$(head -c 24 /dev/urandom | base64)"
cd claude_flutter_app/termux_agent_server
node agent_server.js
```

Then in the app's Settings, turn on **Coding tools** and paste the same
`CLAUDE_AGENT_KEY` value. Full details: `termux_agent_server/README.md`.

## Memory

`save_memory` lets the model store a short fact on its own when you tell it
something worth remembering ("my name is Sara", "I'm vegetarian"). All
saved facts get added to the system prompt on every request. You can also
view/add/remove facts directly in **Settings → Memory**.

## System prompt

Editable in **Settings → System prompt**. Two placeholders are resolved
automatically before each request: `{{date}}` and `{{time}}`, using the
phone's current date/time — this is what makes the assistant aware of "now"
without needing a clock tool.


## Your setup: 9Router in Termux + this app, same phone

This build is specifically wired for running **9Router inside Termux** on
the same Android phone that runs this app. Because both live on one device,
`localhost` correctly refers to the phone itself — no `10.0.2.2`, no LAN IP
needed. The only extra step this requires is telling Android it's okay to
make a plain (non-HTTPS) request to `localhost`, since Android blocks
cleartext HTTP by default from API 28 onward. That's already handled by the
`network_security_config.xml` and `scripts/patch_android.py` included here.

## One-time setup (do this locally — this environment has no Flutter SDK)

```bash
cd claude_flutter_app

# 1. Scaffold the native platform folders (android/, ios/, etc.).
#    It will not overwrite lib/ or pubspec.yaml, and it will not overwrite
#    android/app/src/main/res/xml/network_security_config.xml since that
#    file already exists in this project.
flutter create .

# 2. Patch the freshly generated AndroidManifest.xml to add the INTERNET
#    permission and point the app at network_security_config.xml.
#    (Safe to re-run; it only inserts what's missing.)
python3 scripts/patch_android.py

# 3. Fetch dependencies
flutter pub get

# 4. Run it, with Termux + 9Router already running on the same phone
flutter run
```

**If the build complains about `compileSdk`:** open
`android/app/build.gradle.kts` and check the `compileSdk` value. Some
plugins (like the markdown renderer used here) need a newer Android SDK
than the Flutter template defaults to — bump it to `36` if the build asks
for it.

## Connecting to 9Router (in Termux, on this phone)

1. In Termux, start 9Router as you normally would (e.g. `npm run dev` /
   `npm run start`) so it's listening on `http://localhost:20128`.
2. Keep Termux alive in the background: run `termux-wake-lock` in the same
   session (needs the Termux:API add-on), and disable battery optimization
   for Termux in Android's app settings — otherwise Android may suspend it
   while you're using the chat app and requests will fail.
3. Grab an API key from the 9Router dashboard (`http://localhost:20128/dashboard`
   in a browser on the phone).
4. In the app, open the drawer → gear icon → **Settings**:
   - **Base URL** is already defaulted to `http://localhost:20128/v1` — no
     change needed.
   - **API key**: paste the key from the dashboard.
5. Tap **Test connection & fetch models**, then pick a model — from
   Settings or from the model selector in the chat app bar.

If the connection test fails, double check in Termux that 9Router is still
running (`termux-wake-lock` can get dropped if Termux itself was killed),
and that you copied the API key correctly.

## Notes / next steps

- The attach button opens a sheet with three options: choose a photo,
  take a photo, or **add a code file / .zip**. Photos are sent as
  OpenAI-style `image_url` parts (needs a vision-capable model in
  9Router). Code/text files are read as plain text and folded into your
  message as a labeled fenced code block — no API changes needed, since
  it's all just text under the hood (`lib/services/file_attachment_service.dart`).
  A `.zip` gets unpacked in memory (via the `archive` package) and every
  text/code file inside it is added the same way, skipping binaries and
  anything over 200KB per file / 400KB combined, with a short note if
  anything got skipped.
- Only recognized text/code extensions are accepted (`.py`, `.js`, `.dart`,
  `.json`, `.md`, `.yaml`, `.sql`, `.html`, `.css`, and quite a few more —
  see `FileAttachmentService._textExtensions`). PDFs, Word docs, and other
  binary formats aren't supported yet — that would need a text-extraction
  step per format (e.g. a PDF text extractor) rather than "just read the
  bytes as UTF-8".
- Conversations persist locally via `SharedPreferences` as JSON. If chat
  history grows large, swap `StorageService` for `sqflite`/`drift` without
  touching the rest of the app — `ChatProvider` only calls
  `loadConversations()`/`saveConversations()`. Note that images are stored
  as base64 inline in that JSON, so a chat with several photos (or a big
  zip's worth of code) will take up noticeably more local storage than a
  text-only one.
- Voice input isn't implemented; `speech_to_text` would be the natural
  addition for a mic button next to the send button.
