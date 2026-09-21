import 'dart:convert';
import 'package:http/http.dart' as http;

class AgentApiException implements Exception {
  final String message;
  AgentApiException(this.message);
  @override
  String toString() => message;
}

/// Talks to the small Node.js `agent_server.js` running in Termux, which
/// gives us confined shell/file access on the phone (see
/// termux_agent_server/README.md for what it does and why it's separate
/// from 9Router).
class AgentApiService {
  final String baseUrl; // e.g. http://localhost:8765
  final String agentKey;

  AgentApiService({required this.baseUrl, required this.agentKey});

  String get _cleanBase =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<Map<String, dynamic>> _post(String route, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_cleanBase/$route');
    http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json', 'X-Agent-Key': agentKey},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw AgentApiException(
          'Could not reach the agent server at $_cleanBase. Is agent_server.js running in Termux? ($e)');
    }
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw AgentApiException('Agent server returned an unexpected response (${resp.statusCode}).');
    }
    if (resp.statusCode != 200) {
      throw AgentApiException(decoded['error']?.toString() ?? 'Agent server error (${resp.statusCode})');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> health() async {
    final uri = Uri.parse('$_cleanBase/health');
    final resp = await http.get(uri).timeout(const Duration(seconds: 5));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> runShell(String command, {int timeoutMs = 15000}) =>
      _post('run_shell', {'command': command, 'timeoutMs': timeoutMs});

  Future<Map<String, dynamic>> readFile(String path) => _post('read_file', {'path': path});

  Future<Map<String, dynamic>> writeFile(String path, String content) =>
      _post('write_file', {'path': path, 'content': content});

  Future<Map<String, dynamic>> listDir(String path) => _post('list_dir', {'path': path});
}
