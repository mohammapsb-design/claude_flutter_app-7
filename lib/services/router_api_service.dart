import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/chat_message.dart';

class RouterApiException implements Exception {
  final String message;
  RouterApiException(this.message);
  @override
  String toString() => message;
}

/// The outcome of one streamed chat-completion turn: some amount of text
/// content (already delivered incrementally via [onContent] as it arrived)
/// plus, if the model decided to call tools instead of (or before)
/// answering, the accumulated tool calls it asked for.
class ChatCompletionResult {
  final String content;
  final List<ToolCall> toolCalls;
  final String? finishReason;

  ChatCompletionResult({required this.content, required this.toolCalls, this.finishReason});

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// Internal accumulator for one in-progress tool call while its
/// `arguments` string streams in across multiple SSE chunks.
class _ToolCallBuilder {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}

/// Talks to a local 9Router instance (https://github.com/BillyND/9router
/// and compatible forks). 9Router exposes an OpenAI-compatible API:
///   GET  {baseUrl}/models
///   POST {baseUrl}/chat/completions   (supports "stream": true, SSE,
///                                      and OpenAI-style "tools"/function
///                                      calling)
class RouterApiService {
  final String baseUrl; // e.g. http://localhost:20128/v1
  final String apiKey;
  http.Client? _activeClient;

  RouterApiService({required this.baseUrl, required this.apiKey});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      };

  String get _cleanBase =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  /// Fetches the list of model ids available through the router.
  Future<List<String>> fetchModels() async {
    final uri = Uri.parse('$_cleanBase/models');
    final http.Response resp;
    try {
      resp = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw RouterApiException('Could not reach 9Router at $_cleanBase. Is it running? ($e)');
    }
    if (resp.statusCode != 200) {
      throw RouterApiException('9Router returned ${resp.statusCode}: ${resp.body}');
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = decoded['data'] as List<dynamic>? ?? [];
    return data.map((m) => (m as Map<String, dynamic>)['id'] as String).toList();
  }

  /// Sends one chat-completion turn with streaming enabled. Text deltas are
  /// pushed to [onContent] as they arrive; the returned Future resolves
  /// once the turn is fully done, with the complete text plus any tool
  /// calls the model requested. Call [cancel] to abort mid-stream.
  Future<ChatCompletionResult> sendChat({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    required void Function(String delta) onContent,
  }) async {
    final uri = Uri.parse('$_cleanBase/chat/completions');
    final body = <String, dynamic>{
      'model': model,
      'stream': true,
      'messages': messages,
    };
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
    }

    final request = http.Request('POST', uri)
      ..headers.addAll(_headers)
      ..body = jsonEncode(body);

    final client = http.Client();
    _activeClient = client;

    late final http.StreamedResponse response;
    try {
      response = await client.send(request);
    } catch (e) {
      client.close();
      throw RouterApiException('Could not reach 9Router at $_cleanBase. Is it running? ($e)');
    }

    if (response.statusCode != 200) {
      final errBody = await response.stream.bytesToString();
      client.close();
      throw RouterApiException('9Router returned ${response.statusCode}: $errBody');
    }

    final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());
    final contentBuffer = StringBuffer();
    final toolCallBuilders = <int, _ToolCallBuilder>{};
    String? finishReason;

    try {
      await for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') break;

        Map<String, dynamic> json;
        try {
          json = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue; // skip malformed keep-alive/comment lines
        }

        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;
        final choice = choices.first as Map<String, dynamic>;
        finishReason = (choice['finish_reason'] as String?) ?? finishReason;

        final delta = choice['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;

        final content = delta['content'] as String?;
        if (content != null && content.isNotEmpty) {
          contentBuffer.write(content);
          onContent(content);
        }

        final toolCallDeltas = delta['tool_calls'] as List<dynamic>?;
        if (toolCallDeltas != null) {
          for (final raw in toolCallDeltas) {
            final tc = raw as Map<String, dynamic>;
            final index = (tc['index'] as num?)?.toInt() ?? 0;
            final builder = toolCallBuilders.putIfAbsent(index, () => _ToolCallBuilder());
            final id = tc['id'] as String?;
            if (id != null && id.isNotEmpty) builder.id = id;
            final function = tc['function'] as Map<String, dynamic>?;
            if (function != null) {
              final name = function['name'] as String?;
              if (name != null && name.isNotEmpty) builder.name = name;
              final args = function['arguments'] as String?;
              if (args != null) builder.arguments.write(args);
            }
          }
        }
      }
    } finally {
      client.close();
      _activeClient = null;
    }

    final toolCalls = toolCallBuilders.values
        .where((b) => b.name.isNotEmpty)
        .map((b) => ToolCall(
              id: b.id.isEmpty ? 'call_${b.name}_${b.hashCode}' : b.id,
              name: b.name,
              argumentsJson: b.arguments.toString(),
            ))
        .toList();

    return ChatCompletionResult(
      content: contentBuffer.toString(),
      toolCalls: toolCalls,
      finishReason: finishReason,
    );
  }

  /// Cancels any in-flight streaming request.
  void cancel() {
    _activeClient?.close();
    _activeClient = null;
  }
}
