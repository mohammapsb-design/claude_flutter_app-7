import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/chat_message.dart';
import '../theme/app_theme.dart';

/// One fenced code block or plain-text run, used to split a message's
/// markdown into alternating segments so code blocks can get their own
/// header + copy button instead of flutter_markdown's plain rendering.
class _Segment {
  final bool isCode;
  final String text; // code content, or plain markdown text
  final String language;
  _Segment.code(this.text, this.language) : isCode = true;
  _Segment.text(this.text)
      : isCode = false,
        language = '';
}

List<_Segment> _splitCodeBlocks(String content) {
  final pattern = RegExp(r'```([a-zA-Z0-9_+-]*)\n([\s\S]*?)```', multiLine: true);
  final segments = <_Segment>[];
  var lastEnd = 0;
  for (final match in pattern.allMatches(content)) {
    if (match.start > lastEnd) {
      segments.add(_Segment.text(content.substring(lastEnd, match.start)));
    }
    final lang = match.group(1) ?? '';
    final code = match.group(2) ?? '';
    segments.add(_Segment.code(code.trimRight(), lang));
    lastEnd = match.end;
  }
  if (lastEnd < content.length) {
    segments.add(_Segment.text(content.substring(lastEnd)));
  }
  if (segments.isEmpty) segments.add(_Segment.text(content));
  return segments;
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;

  const ChatBubble({super.key, required this.message, this.onEdit, this.onRegenerate});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.role == MessageRole.user;

    Widget content;
    if (isUser) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.accentSoftDark : AppColors.accentSoft,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.radiusLarge),
                  topRight: Radius.circular(AppTheme.radiusLarge),
                  bottomLeft: Radius.circular(AppTheme.radiusLarge),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.attachments != null && message.attachments!.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: message.attachments!
                          .map((a) => ClipRRect(
                                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                                child: Image.memory(
                                  base64Decode(a.base64),
                                  width: 140,
                                  height: 140,
                                  fit: BoxFit.cover,
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (message.videoAttachments != null && message.videoAttachments!.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          message.videoAttachments!.map((v) => _SentVideoChip(video: v)).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (message.textAttachments != null && message.textAttachments!.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: message.textAttachments!.map((f) => _SentFileChip(file: f)).toList(),
                    ),
                    if (message.content.isNotEmpty) const SizedBox(height: 8),
                  ],
                  if (message.content.isNotEmpty)
                    SelectableText(
                      message.content,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4),
                    ),
                ],
              ),
            ),
          ),
          if (message.content.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 18, top: 2, bottom: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CopyIconButton(textToCopy: message.content),
                  if (onEdit != null) ...[
                    const SizedBox(width: 4),
                    _SmallActionIcon(icon: Icons.edit_outlined, tooltip: 'Edit', onTap: onEdit!),
                  ],
                ],
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      );
    } else {
      final segments = _splitCodeBlocks(message.content.isEmpty ? ' ' : message.content);
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.statusText != null) ...[
              _ToolStatusChip(label: message.statusText!),
              const SizedBox(height: 8),
            ],
            for (final segment in segments)
              segment.isCode
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: _CodeBlock(code: segment.text, language: segment.language),
                    )
                  : MarkdownBody(
                      data: segment.text,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                        p: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
                      ),
                    ),
            if (message.isStreaming && message.statusText == null) ...[
              const SizedBox(height: 6),
              _TypingCursor(isDark: isDark),
            ],
            if (message.isError) ...[
              const SizedBox(height: 4),
              Text(
                'Could not complete this response.',
                style: TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
            if (!message.isStreaming && message.content.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CopyIconButton(textToCopy: message.content),
                  if (onRegenerate != null) ...[
                    const SizedBox(width: 4),
                    _SmallActionIcon(
                      icon: Icons.refresh,
                      tooltip: message.isError ? 'Retry' : 'Regenerate',
                      onTap: onRegenerate!,
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      );
    }

    return _FadeInOnce(child: content);
  }
}

/// A small, understated icon button for a one-off action (edit,
/// regenerate) — same visual weight as _CopyIconButton but without the
/// copied/checkmark state.
class _SmallActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _SmallActionIcon({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

/// A small, understated icon button that copies the given text to the
/// clipboard and briefly shows a checkmark for confirmation — used under
/// both user and assistant messages so either side can be copied whole.
class _CopyIconButton extends StatefulWidget {
  final String textToCopy;
  const _CopyIconButton({required this.textToCopy});

  @override
  State<_CopyIconButton> createState() => _CopyIconButtonState();
}

class _CopyIconButtonState extends State<_CopyIconButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.textToCopy));
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary);
    return InkWell(
      onTap: _copy,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(
          _copied ? Icons.check : Icons.copy_outlined,
          size: 15,
          color: _copied ? AppColors.accent : color,
        ),
      ),
    );
  }
}

/// Small chip shown in a sent message for an attached video — no inline
/// playback (that would need a video_player dependency), just an
/// acknowledgment that a video was sent, sized the same as the file chip.
class _SentVideoChip extends StatelessWidget {
  final VideoAttachment video;
  const _SentVideoChip({required this.video});

  @override
  Widget build(BuildContext context) {
    final sizeMb = (video.base64.length * 3 / 4 / (1024 * 1024)).toStringAsFixed(1);
    return Container(
      width: 96,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam, size: 22),
          const SizedBox(height: 4),
          Text('${sizeMb}MB', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Small chip shown in a sent message for an attached text/code file — tap
/// it to view the full content in a sheet, rather than it flooding the
/// bubble inline.
class _SentFileChip extends StatelessWidget {
  final TextFileAttachment file;
  const _SentFileChip({required this.file});

  void _openViewer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          file.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _CopyIconButton(textToCopy: file.content),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      file.content,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sizeKb = (file.content.length / 1024).clamp(0, 999).toStringAsFixed(1);
    return InkWell(
      onTap: () => _openViewer(context),
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Container(
        width: 96,
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceAlt : Colors.black.withOpacity(0.06),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.description_outlined, size: 20),
            const SizedBox(height: 4),
            Text(
              file.name.split('/').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text('${sizeKb}KB', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// A small pill showing what tool is currently running, e.g.
/// "Searching the web for 'weather in Tehran'…".
class _ToolStatusChip extends StatelessWidget {
  final String label;
  const _ToolStatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.accentSoftDark : AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// A code block with a language label and a copy button, styled like a
/// small terminal card rather than plain inline markdown code.
class _CodeBlock extends StatefulWidget {
  final String code;
  final String language;
  const _CodeBlock({required this.code, required this.language});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    HapticFeedback.selectionClick();
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: Container(
        color: bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    widget.language.isEmpty ? 'code' : widget.language,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: _copy,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_copied ? Icons.check : Icons.copy_all_outlined, size: 14),
                          const SizedBox(width: 4),
                          Text(_copied ? 'Copied' : 'Copy', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                widget.code,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades a message in once when it first appears, without re-triggering on
/// every rebuild while it's still streaming — keeps the calm, non-jumpy
/// feel described in the design brief.
class _FadeInOnce extends StatefulWidget {
  final Widget child;
  const _FadeInOnce({required this.child});

  @override
  State<_FadeInOnce> createState() => _FadeInOnceState();
}

class _FadeInOnceState extends State<_FadeInOnce> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      child: widget.child,
    );
  }
}

/// A tiny pulsing dot to indicate the assistant is still streaming,
/// deliberately calm rather than a busy spinner.
class _TypingCursor extends StatefulWidget {
  final bool isDark;
  const _TypingCursor({required this.isDark});

  @override
  State<_TypingCursor> createState() => _TypingCursorState();
}

class _TypingCursorState extends State<_TypingCursor> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_controller),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
      ),
    );
  }
}
