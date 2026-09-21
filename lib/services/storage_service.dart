import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/conversation.dart';

/// Simple local persistence built on SharedPreferences. Good enough for a
/// single-user local app talking to a self-hosted router; swap for
/// sqflite/drift later if conversation volume grows large.
class StorageService {
  static const _conversationsKey = 'conversations_v1';
  static const _baseUrlKey = 'settings_base_url';
  static const _apiKeyKey = 'settings_api_key';
  static const _selectedModelKey = 'settings_selected_model';
  static const _themeModeKey = 'settings_theme_mode'; // system | light | dark
  static const _systemPromptKey = 'settings_system_prompt';
  static const _toolsEnabledKey = 'settings_tools_enabled';
  static const _codingToolsEnabledKey = 'settings_coding_tools_enabled';
  static const _confirmShellCommandsKey = 'settings_confirm_shell_commands';
  static const _agentBaseUrlKey = 'settings_agent_base_url';
  static const _agentKeyKey = 'settings_agent_key';

  Future<List<Conversation>> loadConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_conversationsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveConversations(List<Conversation> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(conversations.map((c) => c.toJson()).toList());
    await prefs.setString(_conversationsKey, raw);
  }

  Future<Map<String, String?>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'baseUrl': prefs.getString(_baseUrlKey),
      'apiKey': prefs.getString(_apiKeyKey),
      'selectedModel': prefs.getString(_selectedModelKey),
      'themeMode': prefs.getString(_themeModeKey),
      'systemPrompt': prefs.getString(_systemPromptKey),
      'toolsEnabled': prefs.getBool(_toolsEnabledKey)?.toString(),
      'codingToolsEnabled': prefs.getBool(_codingToolsEnabledKey)?.toString(),
      'confirmShellCommands': prefs.getBool(_confirmShellCommandsKey)?.toString(),
      'agentBaseUrl': prefs.getString(_agentBaseUrlKey),
      'agentKey': prefs.getString(_agentKeyKey),
    };
  }

  Future<void> saveSystemPrompt(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_systemPromptKey, value);
  }

  Future<void> saveToolsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_toolsEnabledKey, value);
  }

  Future<void> saveCodingToolsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_codingToolsEnabledKey, value);
  }

  Future<void> saveConfirmShellCommands(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_confirmShellCommandsKey, value);
  }

  Future<void> saveAgentBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_agentBaseUrlKey, value);
  }

  Future<void> saveAgentKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_agentKeyKey, value);
  }

  Future<void> saveBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, value);
  }

  Future<void> saveApiKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, value);
  }

  Future<void> saveSelectedModel(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedModelKey, value);
  }

  Future<void> saveThemeMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, value);
  }
}
