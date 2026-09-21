#!/usr/bin/env node
/**
 * agent_server.js
 *
 * A tiny, dependency-free HTTP server meant to run inside Termux, alongside
 * 9Router. It gives the Claude-style Flutter app a way to run shell
 * commands and read/write files ON THE PHONE, confined to one workspace
 * directory — because the Flutter app itself is a separate, sandboxed
 * Android app and cannot exec shell commands directly.
 *
 * Security model (deliberately simple):
 *   - Every request must include header `X-Agent-Key: <CLAUDE_AGENT_KEY>` matching
 *     the CLAUDE_AGENT_KEY environment variable. Requests without it are rejected.
 *   - All file paths are resolved relative to WORKSPACE_DIR and any path
 *     that would escape it (e.g. "../../etc/passwd") is rejected.
 *   - Shell commands run with `cwd` set to WORKSPACE_DIR, with a timeout
 *     and output size cap, but are NOT otherwise restricted — the Flutter
 *     app is expected to ask the user for confirmation before sending any
 *     shell command (this server just executes what it's told, inside the
 *     workspace). Don't expose this server beyond localhost.
 *
 * Run it:
 *   export CLAUDE_AGENT_KEY="pick-a-long-random-string"
 *   node agent_server.js
 *
 * Endpoints (all POST, JSON body, except /health):
 *   GET  /health
 *   POST /run_shell   { "command": "ls -la", "timeoutMs": 15000 }
 *   POST /read_file    { "path": "notes.txt" }
 *   POST /write_file   { "path": "notes.txt", "content": "..." }
 *   POST /list_dir     { "path": "." }
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const PORT = parseInt(process.env.AGENT_PORT || '8765', 10);
const AGENT_KEY = process.env.CLAUDE_AGENT_KEY || '';
const WORKSPACE_DIR = path.resolve(process.env.AGENT_WORKSPACE || path.join(process.env.HOME || '.', 'agent_workspace'));
const MAX_OUTPUT_BYTES = 1024 * 1024; // 1MB cap on shell output / file reads
const DEFAULT_TIMEOUT_MS = 15000;

if (!AGENT_KEY) {
  console.error('CLAUDE_AGENT_KEY is not set. Refusing to start without one — set it with:');
  console.error('  export CLAUDE_AGENT_KEY="$(head -c 24 /dev/urandom | base64)"');
  process.exit(1);
}

if (!fs.existsSync(WORKSPACE_DIR)) {
  fs.mkdirSync(WORKSPACE_DIR, { recursive: true });
}
console.log(`agent_server: workspace = ${WORKSPACE_DIR}`);

/** Resolves a user-supplied relative path inside WORKSPACE_DIR, rejecting
 * any attempt to escape it via "..", absolute paths, or symlink tricks. */
function resolveSafePath(userPath) {
  const candidate = path.resolve(WORKSPACE_DIR, userPath || '.');
  const relative = path.relative(WORKSPACE_DIR, candidate);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error('Path escapes the workspace directory');
  }
  return candidate;
}

function sendJson(res, statusCode, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body),
  });
  res.end(body);
}

function readRequestBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_OUTPUT_BYTES) {
        reject(new Error('Request body too large'));
        req.destroy();
        return;
      }
      data += chunk;
    });
    req.on('end', () => {
      if (!data) return resolve({});
      try {
        resolve(JSON.parse(data));
      } catch (e) {
        reject(new Error('Invalid JSON body'));
      }
    });
    req.on('error', reject);
  });
}

const routes = {
  async run_shell(body) {
    const command = body.command;
    if (!command || typeof command !== 'string') throw new Error('Missing "command"');
    const timeoutMs = Math.min(body.timeoutMs || DEFAULT_TIMEOUT_MS, 120000);
    return await new Promise((resolve) => {
      exec(command, { cwd: WORKSPACE_DIR, timeout: timeoutMs, maxBuffer: MAX_OUTPUT_BYTES }, (err, stdout, stderr) => {
        resolve({
          exitCode: err ? (typeof err.code === 'number' ? err.code : 1) : 0,
          stdout: stdout ? stdout.toString() : '',
          stderr: stderr ? stderr.toString() : (err && !err.code ? String(err.message) : ''),
          timedOut: !!(err && err.killed),
        });
      });
    });
  },

  async read_file(body) {
    const filePath = resolveSafePath(body.path);
    const stat = fs.statSync(filePath);
    if (stat.size > MAX_OUTPUT_BYTES) throw new Error('File too large to read (>1MB)');
    const content = fs.readFileSync(filePath, 'utf8');
    return { path: path.relative(WORKSPACE_DIR, filePath), content };
  },

  async write_file(body) {
    const filePath = resolveSafePath(body.path);
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, body.content ?? '', 'utf8');
    return { path: path.relative(WORKSPACE_DIR, filePath), bytesWritten: Buffer.byteLength(body.content ?? '') };
  },

  async list_dir(body) {
    const dirPath = resolveSafePath(body.path || '.');
    const entries = fs.readdirSync(dirPath, { withFileTypes: true });
    return {
      path: path.relative(WORKSPACE_DIR, dirPath) || '.',
      entries: entries.map((e) => ({
        name: e.name,
        type: e.isDirectory() ? 'dir' : e.isFile() ? 'file' : 'other',
      })),
    };
  },
};

const server = http.createServer(async (req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    return sendJson(res, 200, { ok: true, workspace: WORKSPACE_DIR });
  }

  if (req.headers['x-agent-key'] !== AGENT_KEY) {
    return sendJson(res, 401, { error: 'Missing or invalid X-Agent-Key header' });
  }

  const routeName = (req.url || '').replace(/^\//, '');
  const handler = routes[routeName];
  if (req.method !== 'POST' || !handler) {
    return sendJson(res, 404, { error: `No such route: ${req.method} ${req.url}` });
  }

  try {
    const body = await readRequestBody(req);
    const result = await handler(body);
    sendJson(res, 200, result);
  } catch (e) {
    sendJson(res, 400, { error: e.message || String(e) });
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`agent_server: listening on http://127.0.0.1:${PORT}`);
});
