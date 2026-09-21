import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../services/memory_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  late final TextEditingController _systemPromptController;
  late final TextEditingController _agentUrlController;
  late final TextEditingController _agentKeyController;
  final _memory = MemoryService();
  List<String> _facts = [];
  final _newFactController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _urlController = TextEditingController(text: settings.baseUrl);
    _keyController = TextEditingController(text: settings.apiKey);
    _systemPromptController = TextEditingController(text: settings.systemPrompt);
    _agentUrlController = TextEditingController(text: settings.agentBaseUrl);
    _agentKeyController = TextEditingController(text: settings.agentKey);
    _loadFacts();
  }

  Future<void> _loadFacts() async {
    final facts = await _memory.loadFacts();
    if (mounted) setState(() => _facts = facts);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    _systemPromptController.dispose();
    _agentUrlController.dispose();
    _agentKeyController.dispose();
    _newFactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('9Router connection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Point this app at 9Router running in Termux on this same '
            'phone — "localhost" works as-is since both run on one device. '
            'Make sure Termux is running (ideally with termux-wake-lock so '
            'Android doesn\'t kill it in the background).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'http://localhost:20128/v1',
            ),
            onChanged: (v) => settings.updateBaseUrl(v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API key (from the 9Router dashboard)',
            ),
            onChanged: (v) => settings.updateApiKey(v),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => settings.refreshModels(),
              icon: const Icon(Icons.wifi_tethering, size: 18),
              label: const Text('Test connection & fetch models'),
            ),
          ),
          const SizedBox(height: 8),
          _ConnectionStatusBanner(settings: settings),

          const SizedBox(height: 24),
          Text('Available models', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (settings.availableModels.isEmpty)
            Text('No models loaded yet.', style: Theme.of(context).textTheme.bodySmall)
          else
            _ModelListSection(
              models: settings.availableModels,
              selectedModel: settings.selectedModel,
              onSelect: (m) => settings.selectModel(m),
            ),

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('Tools', style: Theme.of(context).textTheme.titleMedium),
              ),
              Switch(
                value: settings.toolsEnabled,
                onChanged: (v) => settings.updateToolsEnabled(v),
              ),
            ],
          ),
          Text(
            'Lets the model use a calculator, web search, and its memory '
            'when it needs to, instead of guessing.',
            style: Theme.of(context).textTheme.bodySmall,
          ),

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('Coding tools', style: Theme.of(context).textTheme.titleMedium),
              ),
              Switch(
                value: settings.codingToolsEnabled,
                onChanged: settings.toolsEnabled
                    ? (v) => settings.updateCodingToolsEnabled(v)
                    : null,
              ),
            ],
          ),
          Text(
            'Lets the model run shell commands and read/write files in a '
            'confined workspace on this phone, via a small server '
            '(agent_server.js) running in Termux. Every shell command asks '
            'for your approval first. Off by default — turn on only if you '
            'set that server up (see termux_agent_server/README.md).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (settings.codingToolsEnabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ask before running shell commands',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Switch(
                  value: settings.confirmShellCommands,
                  onChanged: (v) => settings.updateConfirmShellCommands(v),
                ),
              ],
            ),
            if (!settings.confirmShellCommands)
              Text(
                'Off: commands run immediately, no prompt. Only turn this off if you '
                'trust what you\'re asking the model to do.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _agentUrlController,
              decoration: const InputDecoration(
                labelText: 'Agent server URL',
                hintText: 'http://localhost:8765',
              ),
              onChanged: (v) => settings.updateAgentBaseUrl(v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _agentKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Agent key (must match CLAUDE_AGENT_KEY in Termux)',
              ),
              onChanged: (v) => settings.updateAgentKey(v),
            ),
          ],

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('System prompt', style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton(
                onPressed: () async {
                  await settings.resetSystemPrompt();
                  _systemPromptController.text = settings.systemPrompt;
                },
                child: const Text('Reset to default'),
              ),
            ],
          ),
          TextField(
            controller: _systemPromptController,
            maxLines: 8,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'How should the assistant behave?',
              alignLabelWithHint: true,
            ),
            onChanged: (v) => settings.updateSystemPrompt(v),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'You can use {{date}} and {{time}} — they\'ll be replaced with '
              'the current date/time on every message.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),

          const SizedBox(height: 24),
          Text('Memory', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Short facts the assistant remembers across all chats. It can '
            'add to this itself when you tell it something worth keeping, '
            'or you can add facts directly here.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newFactController,
                  decoration: const InputDecoration(hintText: 'e.g. My name is Sara'),
                  onSubmitted: (_) => _addFact(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_circle, color: AppColors.accent),
                onPressed: _addFact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_facts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Nothing remembered yet.', style: Theme.of(context).textTheme.bodySmall),
            )
          else
            ...List.generate(_facts.length, (index) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_facts[index]),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () async {
                    await _memory.removeFactAt(index);
                    _loadFacts();
                  },
                ),
              );
            }),

          const SizedBox(height: 24),
          Text('Backup & restore', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Chats live only on this phone. Export them to a file you can keep '
            'somewhere safe, and import that file back in (on this phone or a new one).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportBackup,
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Export all'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importBackup,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Import'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => settings.updateThemeMode(s.first),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _addFact() async {
    final text = _newFactController.text.trim();
    if (text.isEmpty) return;
    await _memory.addFact(text);
    _newFactController.clear();
    _loadFacts();
  }

  Future<void> _exportBackup() async {
    final chat = context.read<ChatProvider>();
    if (chat.conversations.isEmpty) {
      _showSnack('No conversations to export yet.');
      return;
    }
    try {
      final jsonStr = chat.exportAllAsJson();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/claude_chat_backup.json');
      await file.writeAsString(jsonStr);
      await Share.shareXFiles([XFile(file.path)], text: 'Claude-style chat backup');
    } catch (e) {
      _showSnack('Could not export: $e');
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true, type: FileType.any);
      final picked = result?.files.single;
      if (picked == null || picked.bytes == null) return;
      final jsonStr = utf8.decode(picked.bytes!);
      final chat = context.read<ChatProvider>();
      final count = await chat.importFromJson(jsonStr);
      _showSnack('Imported $count conversation(s).');
    } catch (e) {
      _showSnack('Could not import: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ConnectionStatusBanner extends StatelessWidget {
  final SettingsProvider settings;
  const _ConnectionStatusBanner({required this.settings});

  @override
  Widget build(BuildContext context) {
    switch (settings.status) {
      case ConnectionStatus.checking:
        return const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Connecting…'),
          ],
        );
      case ConnectionStatus.connected:
        return Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Text('Connected · ${settings.availableModels.length} models found'),
          ],
        );
      case ConnectionStatus.failed:
        return Text(
          settings.lastError ?? 'Connection failed.',
          style: const TextStyle(color: AppColors.error),
        );
      case ConnectionStatus.unknown:
        return const SizedBox.shrink();
    }
  }
}

/// A collapsible model picker: collapsed, it's just one row showing the
/// current model. Expanded, it shows a search field and a
/// height-bounded, virtualized list — so this stays usable whether
/// 9Router reports 5 models or 500.
class _ModelListSection extends StatefulWidget {
  final List<String> models;
  final String? selectedModel;
  final ValueChanged<String> onSelect;

  const _ModelListSection({
    required this.models,
    required this.selectedModel,
    required this.onSelect,
  });

  @override
  State<_ModelListSection> createState() => _ModelListSectionState();
}

class _ModelListSectionState extends State<_ModelListSection> {
  bool _expanded = false;
  String _query = '';

  List<String> get _filtered {
    if (_query.trim().isEmpty) return widget.models;
    final q = _query.toLowerCase();
    return widget.models.where((m) => m.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.selectedModel ?? 'Choose a model',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${widget.models.length} available',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 8),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search models',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              height: 260,
              child: _filtered.isEmpty
                  ? Center(
                      child: Text('No matches for "$_query"',
                          style: Theme.of(context).textTheme.bodySmall),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final model = _filtered[index];
                        return RadioListTile<String>(
                          value: model,
                          groupValue: widget.selectedModel,
                          dense: true,
                          title: Text(model, overflow: TextOverflow.ellipsis),
                          onChanged: (v) {
                            if (v != null) widget.onSelect(v);
                          },
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
