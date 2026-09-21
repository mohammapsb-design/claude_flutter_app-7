import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'services/memory_service.dart';
import 'services/storage_service.dart';
import 'services/tool_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ClaudeStyleApp());
}

class ClaudeStyleApp extends StatefulWidget {
  const ClaudeStyleApp({super.key});

  @override
  State<ClaudeStyleApp> createState() => _ClaudeStyleAppState();
}

class _ClaudeStyleAppState extends State<ClaudeStyleApp> {
  final _storage = StorageService();
  final _memory = MemoryService();
  late final ToolService _toolService = ToolService();
  late final SettingsProvider _settingsProvider = SettingsProvider(_storage);
  late final ChatProvider _chatProvider =
      ChatProvider(_storage, _settingsProvider, _toolService, _memory);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _settingsProvider.load();
    await _chatProvider.load();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _settingsProvider),
        ChangeNotifierProvider.value(value: _chatProvider),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) => MaterialApp(
          title: 'Claude-style Chat',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.themeMode,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
