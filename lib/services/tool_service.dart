import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'agent_service.dart';
import 'expression_evaluator.dart';
import 'memory_service.dart';

/// Everything a tool might need while it executes, built fresh for each
/// send so it always reflects the latest settings — mirrors how
/// RouterApiService is rebuilt per request rather than cached.
class ToolContext {
  final MemoryService memory;
  final AgentApiService agent;

  /// Ask the user to approve or deny an action before it runs. Resolves to
  /// true if approved. Used by run_shell (when confirmShellCommands is on)
  /// so nothing executes on the phone without an explicit tap.
  final Future<bool> Function(String message) confirmAction;

  /// When false, run_shell executes immediately without asking — an
  /// explicit opt-out the user can flip in Settings if the prompts get
  /// tedious for their own trusted workflow.
  final bool confirmShellCommands;

  ToolContext({
    required this.memory,
    required this.agent,
    required this.confirmAction,
    this.confirmShellCommands = true,
  });
}

/// One OpenAI-style function-calling tool: its schema (sent to the model
/// so it knows the tool exists and how to call it) plus the Dart code that
/// actually runs when the model asks to call it.
class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final Future<String> Function(Map<String, dynamic> args, ToolContext ctx) execute;

  /// Short human-readable label shown in the UI while this tool runs,
  /// e.g. "Calculating 12 * 7…". Falls back to a generic label if omitted.
  final String Function(Map<String, dynamic> args)? statusLabel;

  ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
    this.statusLabel,
  });

  Map<String, dynamic> toApiSchema() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };

  String labelFor(Map<String, dynamic> args) => statusLabel?.call(args) ?? 'Using $name…';
}

class ToolService {
  /// The always-on, low-risk tools.
  late final List<ToolDefinition> baseTools = [
    ToolDefinition(
      name: 'calculator',
      description:
          'Evaluate a numeric arithmetic expression (supports + - * / % ^ and parentheses). '
          'Use this for any nontrivial arithmetic instead of computing it yourself.',
      parameters: {
        'type': 'object',
        'properties': {
          'expression': {'type': 'string', 'description': 'e.g. "(12 + 8) * 3 / 2"'},
        },
        'required': ['expression'],
      },
      statusLabel: (args) => 'Calculating ${args['expression'] ?? ''}…',
      execute: (args, ctx) async {
        final expression = args['expression']?.toString() ?? '';
        try {
          final result = ExpressionEvaluator.evaluate(expression);
          return jsonEncode({'expression': expression, 'result': result});
        } catch (e) {
          return jsonEncode({'expression': expression, 'error': 'Could not evaluate: $e'});
        }
      },
    ),
    ToolDefinition(
      name: 'web_search',
      description:
          'Search the web for current information (news, facts, prices, anything that might '
          'have changed recently). Returns a short summary with source titles.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'What to search for'},
        },
        'required': ['query'],
      },
      statusLabel: (args) => 'Searching the web for "${args['query'] ?? ''}"…',
      execute: (args, ctx) async {
        final query = args['query']?.toString() ?? '';
        if (query.isEmpty) return jsonEncode({'error': 'Empty query'});
        try {
          return await _webSearch(query);
        } catch (e) {
          return jsonEncode({'error': 'Web search failed: $e'});
        }
      },
    ),
    ToolDefinition(
      name: 'save_memory',
      description:
          'Save a short fact about the user for future conversations (e.g. their name, '
          'preferences, ongoing projects). Only call this when the user shares something '
          'worth remembering long-term, or explicitly asks you to remember it.',
      parameters: {
        'type': 'object',
        'properties': {
          'fact': {
            'type': 'string',
            'description': 'A short, self-contained fact, e.g. "User\'s name is Sara".',
          },
        },
        'required': ['fact'],
      },
      statusLabel: (args) => 'Remembering that…',
      execute: (args, ctx) async {
        final fact = args['fact']?.toString() ?? '';
        if (fact.isEmpty) return jsonEncode({'error': 'Empty fact'});
        await ctx.memory.addFact(fact);
        return jsonEncode({'saved': fact});
      },
    ),
  ];

  /// Coding tools — opt-in only (see Settings → Tools → "Coding tools").
  /// These reach a real shell/file system on the phone via agent_server.js
  /// running in Termux, so they're kept separate from the always-on tools.
  late final List<ToolDefinition> codingTools = [
    ToolDefinition(
      name: 'run_shell',
      description:
          'Run a shell command in the user\'s Termux workspace on their phone. Use this to '
          'run code, install packages, use git, or inspect the project. The user will be '
          'asked to approve each command before it runs — if they deny it, you\'ll be told so.',
      parameters: {
        'type': 'object',
        'properties': {
          'command': {'type': 'string', 'description': 'e.g. "python3 script.py" or "ls -la"'},
        },
        'required': ['command'],
      },
      statusLabel: (args) => 'Wants to run: ${args['command'] ?? ''}',
      execute: (args, ctx) async {
        final command = args['command']?.toString() ?? '';
        if (command.isEmpty) return jsonEncode({'error': 'Empty command'});

        if (ctx.confirmShellCommands) {
          final approved = await ctx.confirmAction('Run this command on your phone?\n\n$command');
          if (!approved) {
            return jsonEncode({'cancelled': true, 'note': 'The user declined to run this command.'});
          }
        }

        try {
          final result = await ctx.agent.runShell(command);
          return jsonEncode(result);
        } catch (e) {
          return jsonEncode({'error': e.toString()});
        }
      },
    ),
    ToolDefinition(
      name: 'read_file',
      description: 'Read a text file from the user\'s Termux workspace.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': 'Path relative to the workspace, e.g. "main.py"'},
        },
        'required': ['path'],
      },
      statusLabel: (args) => 'Reading ${args['path'] ?? ''}…',
      execute: (args, ctx) async {
        try {
          final result = await ctx.agent.readFile(args['path']?.toString() ?? '');
          return jsonEncode(result);
        } catch (e) {
          return jsonEncode({'error': e.toString()});
        }
      },
    ),
    ToolDefinition(
      name: 'write_file',
      description:
          'Create or overwrite a text file in the user\'s Termux workspace. Use this to write '
          'code or save output — prefer this over pasting large files into the chat.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': 'Path relative to the workspace'},
          'content': {'type': 'string', 'description': 'Full file content to write'},
        },
        'required': ['path', 'content'],
      },
      statusLabel: (args) => 'Writing ${args['path'] ?? ''}…',
      execute: (args, ctx) async {
        try {
          final result = await ctx.agent.writeFile(
            args['path']?.toString() ?? '',
            args['content']?.toString() ?? '',
          );
          return jsonEncode(result);
        } catch (e) {
          return jsonEncode({'error': e.toString()});
        }
      },
    ),
    ToolDefinition(
      name: 'list_dir',
      description: 'List files and folders in a directory in the user\'s Termux workspace.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Path relative to the workspace, e.g. "." for the root',
          },
        },
        'required': [],
      },
      statusLabel: (args) => 'Listing ${args['path'] ?? '.'}…',
      execute: (args, ctx) async {
        try {
          final result = await ctx.agent.listDir(args['path']?.toString() ?? '.');
          return jsonEncode(result);
        } catch (e) {
          return jsonEncode({'error': e.toString()});
        }
      },
    ),
  ];

  List<ToolDefinition> activeTools({required bool codingEnabled}) =>
      [...baseTools, if (codingEnabled) ...codingTools];

  List<Map<String, dynamic>> apiSchemas({required bool codingEnabled}) =>
      activeTools(codingEnabled: codingEnabled).map((t) => t.toApiSchema()).toList();

  ToolDefinition? byName(String name, {required bool codingEnabled}) {
    for (final t in activeTools(codingEnabled: codingEnabled)) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// Uses DuckDuckGo's no-login HTML results page (html.duckduckgo.com),
  /// since the keyless "Instant Answer" API only covers a narrow set of
  /// curated queries (definitions, well-known entities) and returns
  /// nothing for most ordinary searches. This is markup-scraping rather
  /// than an official API, so it can break if DuckDuckGo changes their
  /// HTML — if that happens, this is the one place to fix.
  Future<String> _webSearch(String query) async {
    final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': query});
    final http.Response resp;
    try {
      resp = await http.get(
        uri,
        headers: {
          // A normal browser-like UA avoids DuckDuckGo serving a
          // stripped-down / bot-detection page.
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36',
        },
      ).timeout(const Duration(seconds: 12));
    } catch (e) {
      return jsonEncode({'error': 'Search request failed: $e'});
    }
    if (resp.statusCode != 200) {
      return jsonEncode({'error': 'Search request failed (${resp.statusCode})'});
    }

    final document = html_parser.parse(resp.body);
    final resultNodes = document.querySelectorAll('.result__body');
    final results = <Map<String, String>>[];

    for (final node in resultNodes) {
      if (results.length >= 5) break;
      final titleEl = node.querySelector('.result__a');
      final snippetEl = node.querySelector('.result__snippet');
      final title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) continue;
      final url = _unwrapDuckDuckGoRedirect(titleEl?.attributes['href'] ?? '');
      final snippet = snippetEl?.text.trim() ?? '';
      results.add({'title': title, 'url': url, 'snippet': snippet});
    }

    if (results.isEmpty) {
      return jsonEncode({'query': query, 'note': 'No results found for this query.'});
    }
    return jsonEncode({'query': query, 'results': results});
  }

  /// DuckDuckGo's HTML result links are wrapped in a redirect like
  /// "//duckduckgo.com/l/?uddg=<encoded-real-url>&...". Unwrap it so the
  /// model gets (and can cite) the actual destination URL.
  String _unwrapDuckDuckGoRedirect(String href) {
    if (href.isEmpty) return href;
    final normalized = href.startsWith('//') ? 'https:$href' : href;
    try {
      final uri = Uri.parse(normalized);
      final target = uri.queryParameters['uddg'];
      if (target != null && target.isNotEmpty) return Uri.decodeFull(target);
    } catch (_) {
      // fall through and return the original link below
    }
    return normalized;
  }
}
