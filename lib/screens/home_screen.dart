import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/conversation_drawer.dart';
import '../widgets/model_selector_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  String? _editingMessageId;
  bool _dialogShowing = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent + 120,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _maybeShowConfirmationDialog(ChatProvider chat) async {
    final request = chat.pendingConfirmation;
    if (request == null || _dialogShowing) return;
    _dialogShowing = true;
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Allow this action?'),
        content: Text(request.message, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Deny'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    _dialogShowing = false;
    chat.resolveConfirmation(approved ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final settings = context.watch<SettingsProvider>();
    final convo = chat.current;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      _maybeShowConfirmationDialog(chat);
    });

    return Scaffold(
      drawer: const ConversationDrawer(),
      appBar: AppBar(
        title: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          onTap: () => showModelSelectorSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  settings.selectedModel ?? 'Select a model',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New chat',
            onPressed: () => chat.startNewConversation(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'compact') {
                await chat.compactConversation();
              } else if (value == 'export' && convo != null) {
                final markdown = chat.exportConversationAsMarkdown(convo);
                await Share.share(markdown, subject: convo.title);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'compact', child: Text('Compact this chat')),
              PopupMenuItem(value: 'export', child: Text('Export as Markdown')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: (convo == null || convo.isEmpty)
                  ? _EmptyState(onSuggestionTap: (text) => chat.sendMessage(text))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 12, bottom: 12),
                      itemCount: convo.messages.length,
                      itemBuilder: (context, index) {
                        final message = convo.messages[index];
                        final isLastAssistant = message.role == MessageRole.assistant &&
                            index == convo.messages.length - 1;
                        return ChatBubble(
                          message: message,
                          onEdit: (message.role == MessageRole.user && !chat.isSending)
                              ? () => setState(() {
                                    _editingMessageId = message.id;
                                    _inputController.text = message.content;
                                  })
                              : null,
                          onRegenerate: (isLastAssistant && !chat.isSending)
                              ? () => chat.regenerateResponse()
                              : null,
                        );
                      },
                    ),
            ),
            if (chat.sendError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  chat.sendError!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ),
            ChatInputBar(
              controller: _inputController,
              isSending: chat.isSending,
              editingBannerText: _editingMessageId != null ? 'Editing message' : null,
              onCancelEdit: () => setState(() {
                _editingMessageId = null;
                _inputController.clear();
              }),
              onSend: (text, images, videos, textFiles) {
                final editingId = _editingMessageId;
                if (editingId != null) {
                  setState(() => _editingMessageId = null);
                  chat.editAndResend(editingId, text);
                } else {
                  chat.sendMessage(text, images: images, videos: videos, textFiles: textFiles);
                }
              },
              onStop: () => chat.stopStreaming(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ValueChanged<String> onSuggestionTap;
  const _EmptyState({required this.onSuggestionTap});

  static const _suggestions = [
    'Help me write an email',
    'Explain a tricky concept simply',
    'Brainstorm ideas for me',
    'Debug a piece of code',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text(
              'How can I help you today?',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _suggestions
                  .map(
                    (s) => InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                      onTap: () => onSuggestionTap(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                          border: Border.all(
                            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                          ),
                        ),
                        child: Text(s, style: Theme.of(context).textTheme.bodyMedium),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
