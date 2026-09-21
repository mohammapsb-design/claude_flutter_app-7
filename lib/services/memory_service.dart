import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A deliberately simple long-term memory: a flat list of short fact
/// strings (e.g. "User's name is Ali", "User prefers concise answers")
/// that get folded into every system prompt. No embeddings, no search —
/// just enough to feel like the assistant remembers things about you.
class MemoryService {
  static const _key = 'memory_facts_v1';

  Future<List<String>> loadFacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> saveFacts(List<String> facts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(facts));
  }

  Future<void> addFact(String fact) async {
    final facts = await loadFacts();
    final trimmed = fact.trim();
    if (trimmed.isEmpty || facts.contains(trimmed)) return;
    facts.add(trimmed);
    await saveFacts(facts);
  }

  Future<void> removeFactAt(int index) async {
    final facts = await loadFacts();
    if (index < 0 || index >= facts.length) return;
    facts.removeAt(index);
    await saveFacts(facts);
  }
}
