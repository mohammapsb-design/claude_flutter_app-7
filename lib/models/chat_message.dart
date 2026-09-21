import 'dart:convert';

enum MessageRole { user, assistant, system, tool }

/// A single image attached to a message, sent as a data URL in the
/// OpenAI-style "image_url" content part so vision-capable models can see
/// it. Stored as base64 so it persists as plain JSON like everything else.
class ImageAttachment {
  final String base64;
  final String mimeType; // e.g. "image/jpeg"

  ImageAttachment({required this.base64, required this.mimeType});

  Map<String, dynamic> toJson() => {'base64': base64, 'mimeType': mimeType};

  factory ImageAttachment.fromJson(Map<String, dynamic> json) => ImageAttachment(
        base64: json['base64'] as String,
        mimeType: json['mimeType'] as String,
      );

  String get dataUrl => 'data:$mimeType;base64,$base64';
}

/// A single video attached to a message, sent the same way as
/// [ImageAttachment] but as a "video_url" content part — the same pattern
/// extended to video. Support for this varies by model/router: some
/// multimodal backends accept it, some will ignore or reject it. Kept
/// small deliberately (see size cap in ChatInputBar) since base64 video is
/// heavy to send and to store.
class VideoAttachment {
  final String base64;
  final String mimeType; // e.g. "video/mp4"
  final String fileName;

  VideoAttachment({required this.base64, required this.mimeType, required this.fileName});

  Map<String, dynamic> toJson() => {
        'base64': base64,
        'mimeType': mimeType,
        'fileName': fileName,
      };

  factory VideoAttachment.fromJson(Map<String, dynamic> json) => VideoAttachment(
        base64: json['base64'] as String,
        mimeType: json['mimeType'] as String,
        fileName: json['fileName'] as String? ?? 'video',
      );

  String get dataUrl => 'data:$mimeType;base64,$base64';
}

/// A text/code file (or one extracted from a .zip) attached to a message.
/// Its content is folded into what's actually sent to the model, but kept
/// OUT of the visible `content` shown in the chat bubble — the bubble just
/// shows a small chip per file instead of dumping the whole thing inline.
class TextFileAttachment {
  final String name;
  final String content;

  TextFileAttachment({required this.name, required this.content});

  Map<String, dynamic> toJson() => {'name': name, 'content': content};

  factory TextFileAttachment.fromJson(Map<String, dynamic> json) => TextFileAttachment(
        name: json['name'] as String,
        content: json['content'] as String,
      );
}

/// A single tool invocation the model asked for (OpenAI-style function call).
class ToolCall {
  final String id;
  final String name;
  final String argumentsJson; // raw JSON string, e.g. '{"expression":"2+2"}'

  ToolCall({required this.id, required this.name, required this.argumentsJson});

  Map<String, dynamic> get arguments {
    try {
      return jsonDecode(argumentsJson.isEmpty ? '{}' : argumentsJson) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'argumentsJson': argumentsJson};

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
        id: json['id'] as String,
        name: json['name'] as String,
        argumentsJson: json['argumentsJson'] as String? ?? '{}',
      );

  Map<String, dynamic> toApiJson() => {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': argumentsJson},
      };
}

class ChatMessage {
  final String id;
  final MessageRole role;
  String content;
  final DateTime createdAt;
  bool isStreaming;
  bool isError;

  /// Populated on an assistant message that requested tool calls.
  List<ToolCall>? toolCalls;

  /// Populated on a `tool` role message: which call this is a result for.
  String? toolCallId;
  String? toolName;

  /// Transient UI-only text like "Using calculator…" shown while a tool
  /// runs, cleared once the final answer starts streaming. Not persisted.
  String? statusText;

  /// Images attached to a user message (camera or gallery), sent alongside
  /// the text as OpenAI-style "image_url" content parts.
  List<ImageAttachment>? attachments;

  /// Videos attached to a user message, sent as "video_url" content parts.
  List<VideoAttachment>? videoAttachments;

  /// Text/code files (including ones extracted from a .zip) attached to a
  /// user message. Folded into the API payload, but not into the visible
  /// `content` — see toApiJson().
  List<TextFileAttachment>? textAttachments;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    DateTime? createdAt,
    this.isStreaming = false,
    this.isError = false,
    this.toolCalls,
    this.toolCallId,
    this.toolName,
    this.statusText,
    this.attachments,
    this.videoAttachments,
    this.textAttachments,
  }) : createdAt = createdAt ?? DateTime.now();

  static String _roleName(MessageRole r) => switch (r) {
        MessageRole.user => 'user',
        MessageRole.assistant => 'assistant',
        MessageRole.system => 'system',
        MessageRole.tool => 'tool',
      };

  /// The text actually sent to the model: attached text/code files folded
  /// in as labeled fenced blocks ahead of whatever the user typed. Kept
  /// separate from `content` (which is what the bubble displays) so a
  /// large attached file doesn't flood the visible chat.
  String get _effectiveTextForApi {
    if (textAttachments == null || textAttachments!.isEmpty) return content;
    final buffer = StringBuffer();
    for (final file in textAttachments!) {
      buffer
        ..writeln('File: ${file.name}')
        ..writeln('```')
        ..writeln(file.content)
        ..writeln('```')
        ..writeln();
    }
    buffer.write(content);
    return buffer.toString();
  }

  bool get _hasMultimodalParts =>
      (attachments != null && attachments!.isNotEmpty) ||
      (videoAttachments != null && videoAttachments!.isNotEmpty);

  /// Converts to the JSON shape expected by an OpenAI-compatible
  /// `/v1/chat/completions` request body (what 9Router expects). When
  /// images/videos are attached, `content` becomes an array of
  /// text/image_url/video_url parts; otherwise it stays a plain string for
  /// maximum compatibility with non-vision models. Attached text files are
  /// folded into the text part either way.
  Map<String, dynamic> toApiJson() {
    final effectiveText = _effectiveTextForApi;
    final base = <String, dynamic>{
      'role': _roleName(role),
      'content': _hasMultimodalParts
          ? [
              if (effectiveText.isNotEmpty) {'type': 'text', 'text': effectiveText},
              ...?attachments?.map((a) => {
                    'type': 'image_url',
                    'image_url': {'url': a.dataUrl},
                  }),
              ...?videoAttachments?.map((v) => {
                    'type': 'video_url',
                    'video_url': {'url': v.dataUrl},
                  }),
            ]
          : effectiveText,
    };
    if (role == MessageRole.assistant && toolCalls != null && toolCalls!.isNotEmpty) {
      base['tool_calls'] = toolCalls!.map((t) => t.toApiJson()).toList();
    }
    if (role == MessageRole.tool && toolCallId != null) {
      base['tool_call_id'] = toolCallId;
    }
    return base;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': _roleName(role),
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'toolCalls': toolCalls?.map((t) => t.toJson()).toList(),
        'toolCallId': toolCallId,
        'toolName': toolName,
        'attachments': attachments?.map((a) => a.toJson()).toList(),
        'videoAttachments': videoAttachments?.map((v) => v.toJson()).toList(),
        'textAttachments': textAttachments?.map((f) => f.toJson()).toList(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        role: MessageRole.values.firstWhere((r) => _roleName(r) == json['role']),
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        toolCalls: (json['toolCalls'] as List?)
            ?.map((t) => ToolCall.fromJson(t as Map<String, dynamic>))
            .toList(),
        toolCallId: json['toolCallId'] as String?,
        toolName: json['toolName'] as String?,
        attachments: (json['attachments'] as List?)
            ?.map((a) => ImageAttachment.fromJson(a as Map<String, dynamic>))
            .toList(),
        videoAttachments: (json['videoAttachments'] as List?)
            ?.map((v) => VideoAttachment.fromJson(v as Map<String, dynamic>))
            .toList(),
        textAttachments: (json['textAttachments'] as List?)
            ?.map((f) => TextFileAttachment.fromJson(f as Map<String, dynamic>))
            .toList(),
      );
}
