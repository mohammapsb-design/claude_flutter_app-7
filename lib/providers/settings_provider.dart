import 'package:flutter/material.dart';

import '../services/agent_service.dart';
import '../services/router_api_service.dart';
import '../services/storage_service.dart';

enum ConnectionStatus { unknown, checking, connected, failed }

const String kDefaultSystemPrompt = '''
You are a helpful, direct, and thoughtful personal assistant running on the
user's own phone through a self-hosted router.

- Be concise by default; this is a mobile chat interface, so avoid long
  preambles. Lead with the answer.
- Use markdown: short paragraphs, code blocks with language tags, and
  bullet lists only when they genuinely help scanning.
- When you don't know something current (today's date, recent events,
  prices), say so plainly instead of guessing.
- If a tool is available that would give a better or more current answer,
  use it rather than answering from memory alone.
- Be honest about uncertainty. Never fabricate facts, sources, or numbers.
- Match the user's language (Persian or English) in your reply.''';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;

  // This app and 9Router (running inside Termux) live on the same physical
  // phone, so "localhost" correctly refers to the device itself.
  String baseUrl = 'http://localhost:20128/v1';
  String apiKey = '';
  String? selectedModel;
  List<String> availableModels = [];
  ThemeMode themeMode = ThemeMode.system;
  String systemPrompt = kDefaultSystemPrompt;
  bool toolsEnabled = true;
  bool codingToolsEnabled = false; // opt-in: this one can touch real files/shell
  bool confirmShellCommands = true; // opt-out: ask before every run_shell call
  String agentBaseUrl = 'http://localhost:8765';
  String agentKey = '';

  ConnectionStatus status = ConnectionStatus.unknown;
  String? lastError;

  SettingsProvider(this._storage);

  Future<void> load() async {
    final saved = await _storage.loadSettings();
    baseUrl = saved['baseUrl'] ?? baseUrl;
    apiKey = saved['apiKey'] ?? apiKey;
    selectedModel = saved['selectedModel'];
    systemPrompt = saved['systemPrompt'] ?? kDefaultSystemPrompt;
    toolsEnabled = saved['toolsEnabled'] == null ? true : saved['toolsEnabled'] == 'true';
    codingToolsEnabled = saved['codingToolsEnabled'] == 'true';
    confirmShellCommands =
        saved['confirmShellCommands'] == null ? true : saved['confirmShellCommands'] == 'true';
    agentBaseUrl = saved['agentBaseUrl'] ?? agentBaseUrl;
    agentKey = saved['agentKey'] ?? agentKey;
    final tm = saved['themeMode'];
    if (tm == 'light') themeMode = ThemeMode.light;
    if (tm == 'dark') themeMode = ThemeMode.dark;
    notifyListeners();
    // Try an initial connection so the model list is populated on launch.
    unawaited(refreshModels());
  }

  RouterApiService buildApi() => RouterApiService(baseUrl: baseUrl, apiKey: apiKey);

  AgentApiService buildAgentApi() => AgentApiService(baseUrl: agentBaseUrl, agentKey: agentKey);

  Future<void> updateBaseUrl(String value) async {
    baseUrl = value;
    await _storage.saveBaseUrl(value);
    notifyListeners();
  }

  Future<void> updateApiKey(String value) async {
    apiKey = value;
    await _storage.saveApiKey(value);
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await _storage.saveThemeMode(
      mode == ThemeMode.light ? 'light' : mode == ThemeMode.dark ? 'dark' : 'system',
    );
    notifyListeners();
  }

  Future<void> selectModel(String modelId) async {
    selectedModel = modelId;
    await _storage.saveSelectedModel(modelId);
    notifyListeners();
  }

  Future<void> updateSystemPrompt(String value) async {
    systemPrompt = value;
    await _storage.saveSystemPrompt(value);
    notifyListeners();
  }

  Future<void> resetSystemPrompt() async {
    await updateSystemPrompt(kDefaultSystemPrompt);
  }

  Future<void> updateToolsEnabled(bool value) async {
    toolsEnabled = value;
    await _storage.saveToolsEnabled(value);
    notifyListeners();
  }

  Future<void> updateCodingToolsEnabled(bool value) async {
    codingToolsEnabled = value;
    await _storage.saveCodingToolsEnabled(value);
    notifyListeners();
  }

  Future<void> updateConfirmShellCommands(bool value) async {
    confirmShellCommands = value;
    await _storage.saveConfirmShellCommands(value);
    notifyListeners();
  }

  Future<void> updateAgentBaseUrl(String value) async {
    agentBaseUrl = value;
    await _storage.saveAgentBaseUrl(value);
    notifyListeners();
  }

  Future<void> updateAgentKey(String value) async {
    agentKey = value;
    await _storage.saveAgentKey(value);
    notifyListeners();
  }

  Future<void> refreshModels() async {
    status = ConnectionStatus.checking;
    lastError = null;
    notifyListeners();
    try {
      final models = await buildApi().fetchModels();
      availableModels = models;
      status = ConnectionStatus.connected;
      if (selectedModel == null && models.isNotEmpty) {
        selectedModel = models.first;
        await _storage.saveSelectedModel(models.first);
      }
    } catch (e) {
      status = ConnectionStatus.failed;
      lastError = e.toString();
    }
    notifyListeners();
  }
}

// small helper so we don't need to pull in package:pedantic just for this
void unawaited(Future<void> future) {}
