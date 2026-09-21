import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../services/memory_service.dart';
import '../services/router_api_service.dart';
import '../services/storage_service.dart';
import '../services/tool_service.dart';
import 'settings_provider.dart';

const _uuid = Uuid();
const int _maxToolIterations = 5;

/// Rough context-window safety net: if the combined text we're about to
/// send would be this many characters or more (~4 chars/token, so this is
/// roughly a 15k-token budget), we start dropping the oldest messages
/// rather than risk the request failing outright on a long chat.
const int _maxContextChars = 60000;

/// A pending "are you sure?" prompt raised by a tool (currently just
/// run_shell, and only when confirmShellCommands is on) that the UI should
/// show as a dialog. Resolving it unblocks whichever tool call is awaiting
/// the answer.
class ConfirmationRequest {
  final String message;
  final Completer<bool> _completer = Completer<bool>();
  ConfirmationRequest(this.message);

  Future<bool> get future => _completer.future;
  void resolve(bool approved) {
    if (!_completer.isCompleted) _completer.complete(approved);
  }
}

class ChatProvider extends ChangeNotifier {
  final StorageService _storage;
  final SettingsProvider _settings;
  final ToolService _tools;
  final MemoryService _memory;

  ChatProvider(this._storage, this._settings, this._tools, this._memory);

  List<Conversation> conversations = [];
  Conversation? current;
  bool isSending = false;
  String? sendError;
  RouterApiService? _activeApi;

  ConfirmationRequest? pendingConfirmation;

  Future<void> load() async {
    conversations = await _storage.loadConversations();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (conversations.isNotEmpty) {
      current = conversations.first;
    } else {
      startNewConversation();
    }
    notifyListeners();
  }

  void startNewConversation() {
    final convo = Conversation(id: _uuid.v4(), title: 'New chat');
    conversations.insert(0, convo);
    current = convo;
    sendError = null;
    notifyListeners();
    _persist();
  }

  void selectConversation(String id) {
    final convo = conversations.firstWhere((c) => c.id == id);
    current = convo;
    sendError = null;
    notifyListeners();
  }

  void deleteConversation(String id) {
    conversations.removeWhere((c) => c.id == id);
    if (current?.id == id) {
      current = conversations.isNotEmpty ? conversations.first : null;
      if (current == null) startNewConversation();
    }
    notifyListeners();
    _persist();
  }

  /// Called by the UI (a dialog) once the user taps Allow/Deny.
  void resolveConfirmation(bool approved) {
    pendingConfirmation?.resolve(approved);
    pendingConfirmation = null;
    notifyListeners();
  }

  Future<bool> _requestConfirmation(String message) {
    final request = ConfirmationRequest(message);
    pendingConfirmation = request;
    notifyListeners();
    return request.future;
  }

  Future<void> sendMessage(
    String text, {
    List<ImageAttachment> images = const [],
    List<VideoAttachment> videos = const [],
    List<TextFileAttachment> textFiles = const [],
  }) async {
    if (text.trim().isEmpty && images.isEmpty && videos.isEmpty && textFiles.isEmpty) return;
    if (current == null) return;
    final convo = current!;

    final userMessage = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: text.trim(),
      attachments: images.isEmpty ? null : images,
      videoAttachments: videos.isEmpty ? null : videos,
      textAttachments: textFiles.isEmpty ? null : textFiles,
    );
    convo.messages.add(userMessage);
    if (convo.messages.length == 1) {
      convo.title = text.trim().isNotEmpty
          ? _titleFrom(text)
          : (textFiles.isNotEmpty ? textFiles.first.name : (videos.isNotEmpty ? 'Video' : 'Photo'));
    }
    convo.updatedAt = DateTime.now();

    final assistantMessage = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      content: '',
      isStreaming: true,
    );
    convo.messages.add(assistantMessage);
    notifyListeners();
    _persist();

    await _runAssistantTurn(convo, assistantMessage);
  }

  /// Removes the last assistant reply (whatever it was — a finished answer
  /// or a failed one) and asks the model again using the same history.
  /// Used for both the "Regenerate" button and the "Retry" action on a
  /// failed message.
  Future<void> regenerateResponse() async {
    final convo = current;
    if (convo == null || isSending) return;
    final idx = convo.messages.lastIndexWhere((m) => m.role == MessageRole.assistant);
    if (idx == -1) return;
    convo.messages.removeRange(idx, convo.messages.length);

    final assistantMessage = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      content: '',
      isStreaming: true,
    );
    convo.messages.add(assistantMessage);
    notifyListeners();

    await _runAssistantTurn(convo, assistantMessage);
  }

  /// Discards [messageId] and everything after it, then resends [newText]
  /// as a fresh user message — the simplest correct way to "edit" a past
  /// message without trying to patch a half-sent tool-call history.
  Future<void> editAndResend(String messageId, String newText) async {
    final convo = current;
    if (convo == null || isSending) return;
    final idx = convo.messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    convo.messages.removeRange(idx, convo.messages.length);
    notifyListeners();
    await sendMessage(newText);
  }

  Future<void> _runAssistantTurn(Conversation convo, ChatMessage assistantMessage) async {
    final model = _settings.selectedModel;
    if (model == null) {
      assistantMessage.isError = true;
      assistantMessage.isStreaming = false;
      assistantMessage.content = 'No model selected. Open Settings and connect to 9Router first.';
      sendError = assistantMessage.content;
      notifyListeners();
      _persist();
      return;
    }

    isSending = true;
    sendError = null;
    notifyListeners();
    _persist();

    final api = _settings.buildApi();
    _activeApi = api;

    // Working copy of the API-facing history for this exchange, including
    // the system prompt and any tool call / tool result turns. This is
    // intentionally NOT the same as convo.messages: tool traffic stays out
    // of what's persisted and shown, keeping the visible chat clean.
    var apiMessages = <Map<String, dynamic>>[
      (await _buildSystemMessage()).toApiJson(),
      ...convo.messages
          .where((m) => m.id != assistantMessage.id && !(m.isStreaming && m.content.isEmpty))
          .map((m) => m.toApiJson()),
    ];
    apiMessages = _trimForContext(apiMessages);

    final toolSchemas = _settings.toolsEnabled
        ? _tools.apiSchemas(codingEnabled: _settings.codingToolsEnabled)
        : null;

    final toolContext = ToolContext(
      memory: _memory,
      agent: _settings.buildAgentApi(),
      confirmAction: _requestConfirmation,
      confirmShellCommands: _settings.confirmShellCommands,
    );

    try {
      for (var iteration = 0; iteration < _maxToolIterations; iteration++) {
        final result = await api.sendChat(
          model: model,
          messages: apiMessages,
          tools: toolSchemas,
          onContent: (delta) {
            assistantMessage.statusText = null;
            assistantMessage.content += delta;
            notifyListeners();
          },
        );

        if (!result.hasToolCalls) break;

        // Record the assistant's tool-call turn, then run each tool and
        // feed its result back in, OpenAI-style, before asking again.
        apiMessages.add({
          'role': 'assistant',
          'content': result.content,
          'tool_calls': result.toolCalls.map((t) => t.toApiJson()).toList(),
        });

        for (final call in result.toolCalls) {
          final tool = _tools.byName(call.name, codingEnabled: _settings.codingToolsEnabled);
          assistantMessage.statusText = tool?.labelFor(call.arguments) ?? 'Using ${call.name}…';
          notifyListeners();

          final resultJson = tool == null
              ? '{"error":"Unknown or disabled tool: ${call.name}"}'
              : await tool.execute(call.arguments, toolContext);

          apiMessages.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'content': resultJson,
          });
        }
      }
    } catch (e) {
      assistantMessage.isError = true;
      assistantMessage.content = assistantMessage.content.isEmpty
          ? 'Something went wrong talking to 9Router: $e'
          : assistantMessage.content;
      sendError = e.toString();
    } finally {
      assistantMessage.isStreaming = false;
      assistantMessage.statusText = null;
      isSending = false;
      _activeApi = null;
      convo.updatedAt = DateTime.now();
      notifyListeners();
      _persist();
    }
  }

  void stopStreaming() {
    _activeApi?.cancel();
  }

  /// Drops the oldest non-system messages (one at a time) until the
  /// combined payload is under budget, so a very long chat degrades
  /// gracefully instead of failing outright against the model's context
  /// window. Leaves a short note on the system message when it does this.
  List<Map<String, dynamic>> _trimForContext(List<Map<String, dynamic>> messages) {
    if (messages.length <= 3) return messages;
    final result = List<Map<String, dynamic>>.from(messages);
    var trimmedAny = false;
    while (_estimateChars(result) > _maxContextChars && result.length > 3) {
      result.removeAt(1); // index 0 is always the system message — keep it
      trimmedAny = true;
    }
    if (trimmedAny) {
      final system = result[0];
      result[0] = {
        ...system,
        'content': '${system['content']}\n\n'
            '(Note: some earlier messages in this conversation were left out to fit '
            'the model\'s context window. If the user references something from '
            'earlier that you don\'t have, say so rather than guessing.)',
      };
    }
    return result;
  }

  int _estimateChars(List<Map<String, dynamic>> messages) {
    var total = 0;
    for (final m in messages) {
      final content = m['content'];
      if (content is String) {
        total += content.length;
      } else if (content is List) {
        for (final part in content) {
          if (part is Map && part['type'] == 'text') {
            total += (part['text'] as String?)?.length ?? 0;
          } else {
            total += 200; // rough stand-in weight for an image part
          }
        }
      }
    }
    return total;
  }

  /// Summarizes everything except the last few messages into one compact
  /// note, replacing the originals — an explicit way to shrink a long
  /// chat's footprint rather than relying only on the silent trimming
  /// above. Costs one extra model call.
  Future<void> compactConversation() async {
    final convo = current;
    if (convo == null || isSending) return;
    const keepLast = 4;
    if (convo.messages.length <= keepLast + 1) {
      sendError = 'This chat is already short enough — nothing to compact.';
      notifyListeners();
      return;
    }
    final model = _settings.selectedModel;
    if (model == null) {
      sendError = 'No model selected. Open Settings and connect to 9Router first.';
      notifyListeners();
      return;
    }

    isSending = true;
    sendError = null;
    notifyListeners();

    try {
      final older = convo.messages.sublist(0, convo.messages.length - keepLast);
      final transcript = older
          .map((m) => '${m.role == MessageRole.user ? "User" : "Assistant"}: ${m.content}')
          .join('\n\n');

      final api = _settings.buildApi();
      final summaryBuffer = StringBuffer();
      await api.sendChat(
        model: model,
        messages: [
          {
            'role': 'system',
            'content': 'Summarize the following conversation concisely — a short paragraph '
                'or a few bullet points — preserving names, decisions, and any facts that '
                'matter for continuing the conversation later. Output only the summary.',
          },
          {'role': 'user', 'content': transcript},
        ],
        onContent: (delta) => summaryBuffer.write(delta),
      );

      final summary = summaryBuffer.toString().trim();
      final summaryMessage = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: '📝 Summary of earlier conversation:\n\n'
            '${summary.isEmpty ? "(the model returned an empty summary)" : summary}',
      );
      convo.messages
        ..removeRange(0, convo.messages.length - keepLast)
        ..insert(0, summaryMessage);
      convo.updatedAt = DateTime.now();
    } catch (e) {
      sendError = 'Could not compact this chat: $e';
    } finally {
      isSending = false;
      notifyListeners();
      _persist();
    }
  }

  /// A human-readable Markdown transcript of one conversation, for sharing.
  String exportConversationAsMarkdown(Conversation convo) {
    final buffer = StringBuffer('# ${convo.title}\n\n');
    for (final m in convo.messages) {
      if (m.role == MessageRole.user) {
        buffer.writeln('**You:**\n\n${m.content}\n');
      } else if (m.role == MessageRole.assistant) {
        buffer.writeln('**Assistant:**\n\n${m.content}\n');
      }
    }
    return buffer.toString();
  }

  /// A full-fidelity JSON backup of every conversation, for personal
  /// backup/restore (round-trips through [importFromJson]).
  String exportAllAsJson() => jsonEncode(conversations.map((c) => c.toJson()).toList());

  /// Imports conversations from a JSON string produced by
  /// [exportAllAsJson], inserting them alongside (not replacing) whatever
  /// is already here. Returns how many were imported successfully.
  Future<int> importFromJson(String jsonStr) async {
    List<dynamic> list;
    try {
      list = jsonDecode(jsonStr) as List<dynamic>;
    } catch (e) {
      throw FormatException('That doesn\'t look like a valid backup file: $e');
    }

    var count = 0;
    for (final item in list) {
      try {
        final parsed = Conversation.fromJson(item as Map<String, dynamic>);
        conversations.insert(
          0,
          Conversation(
            id: _uuid.v4(), // re-key to avoid colliding with existing ids
            title: parsed.title,
            messages: parsed.messages,
            createdAt: parsed.createdAt,
            updatedAt: parsed.updatedAt,
          ),
        );
        count++;
      } catch (_) {
        // skip malformed entries rather than failing the whole import
      }
    }
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
    _persist();
    return count;
  }

  Future<ChatMessage> _buildSystemMessage() async {
    final now = DateTime.now();
    var prompt = _settings.systemPrompt
        .replaceAll('{{date}}', DateFormat.yMMMMd().format(now))
        .replaceAll('{{time}}', DateFormat.jm().format(now));

    final facts = await _memory.loadFacts();
    if (facts.isNotEmpty) {
      final factsBlock = facts.map((f) => '- $f').join('\n');
      prompt = '$prompt\n\nThings you remember about this user:\n$factsBlock';
    }

    return ChatMessage(id: 'system', role: MessageRole.system, content: prompt);
  }

  String _titleFrom(String text) {
    final trimmed = text.trim().replaceAll('\n', ' ');
    return trimmed.length > 40 ? '${trimmed.substring(0, 40)}…' : trimmed;
  }

  void _persist() {
    _storage.saveConversations(conversations);
  }
}
