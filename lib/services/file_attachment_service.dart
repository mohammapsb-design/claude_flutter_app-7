import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class ExtractedTextFile {
  final String name;
  final String content;
  ExtractedTextFile(this.name, this.content);
}

/// Turns a picked file into one or more readable text blocks: the file
/// itself if it's plain text/code, or every text/code file found inside it
/// if it's a .zip — all confined by size/count limits so a big archive
/// can't blow up the message payload.
class FileAttachmentService {
  static const maxSingleFileBytes = 200 * 1024; // 200KB per file
  static const maxTotalBytes = 400 * 1024; // 400KB combined per zip
  static const maxZipEntries = 50;

  static const _textExtensions = {
    'py', 'js', 'jsx', 'ts', 'tsx', 'dart', 'java', 'kt', 'kts', 'c', 'h',
    'cpp', 'hpp', 'cc', 'cxx', 'go', 'rs', 'rb', 'php', 'swift', 'm', 'mm',
    'cs', 'scala', 'sh', 'bash', 'zsh', 'ps1', 'sql', 'json', 'yaml', 'yml',
    'toml', 'ini', 'cfg', 'conf', 'md', 'markdown', 'txt', 'csv', 'tsv',
    'html', 'htm', 'css', 'scss', 'less', 'xml', 'gradle', 'properties',
    'env', 'r', 'lua', 'pl', 'vue', 'svelte', 'log',
  };

  static const _knownTextNamesNoExt = {
    'dockerfile', 'makefile', 'readme', 'license', 'gemfile', 'rakefile',
  };

  static const _languageByExtension = {
    'py': 'python', 'js': 'javascript', 'jsx': 'jsx', 'ts': 'typescript',
    'tsx': 'tsx', 'dart': 'dart', 'java': 'java', 'kt': 'kotlin',
    'kts': 'kotlin', 'c': 'c', 'h': 'c', 'cpp': 'cpp', 'hpp': 'cpp',
    'cc': 'cpp', 'cxx': 'cpp', 'go': 'go', 'rs': 'rust', 'rb': 'ruby',
    'php': 'php', 'swift': 'swift', 'cs': 'csharp', 'scala': 'scala',
    'sh': 'bash', 'bash': 'bash', 'zsh': 'bash', 'ps1': 'powershell',
    'sql': 'sql', 'json': 'json', 'yaml': 'yaml', 'yml': 'yaml',
    'toml': 'toml', 'md': 'markdown', 'markdown': 'markdown', 'html': 'html',
    'htm': 'html', 'css': 'css', 'scss': 'scss', 'xml': 'xml', 'vue': 'vue',
    'svelte': 'svelte', 'lua': 'lua', 'pl': 'perl', 'r': 'r',
  };

  static String _extensionOf(String filename) {
    final name = filename.split('/').last.toLowerCase();
    return name.contains('.') ? name.split('.').last : '';
  }

  static bool isLikelyText(String filename) {
    final name = filename.split('/').last.toLowerCase();
    final ext = _extensionOf(filename);
    if (ext.isEmpty) return _knownTextNamesNoExt.contains(name);
    return _textExtensions.contains(ext);
  }

  static String languageFor(String filename) => _languageByExtension[_extensionOf(filename)] ?? '';

  /// Throws a [FormatException] with a user-facing message on any problem
  /// (unsupported type, too large, empty archive, etc).
  static List<ExtractedTextFile> extract(String name, Uint8List bytes) {
    if (name.toLowerCase().endsWith('.zip')) {
      return _extractZip(name, bytes);
    }
    if (!isLikelyText(name)) {
      throw FormatException(
          '"$name" doesn\'t look like a text/code file. Only code/text files and .zip archives are supported right now.');
    }
    if (bytes.length > maxSingleFileBytes) {
      throw FormatException(
          '"$name" is ${(bytes.length / 1024).round()}KB — the limit is ${maxSingleFileBytes ~/ 1024}KB per file.');
    }
    return [ExtractedTextFile(name, _decodeText(bytes))];
  }

  static List<ExtractedTextFile> _extractZip(String zipName, Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('Could not open "$zipName" as a zip: $e');
    }

    final results = <ExtractedTextFile>[];
    var totalBytes = 0;
    var skippedCount = 0;

    for (final entry in archive) {
      if (!entry.isFile) continue;
      if (!isLikelyText(entry.name)) {
        skippedCount++;
        continue;
      }
      final raw = entry.content;
      final data = raw is List<int> ? raw : const <int>[];
      if (data.isEmpty || data.length > maxSingleFileBytes) {
        skippedCount++;
        continue;
      }
      if (totalBytes + data.length > maxTotalBytes || results.length >= maxZipEntries) {
        skippedCount++;
        continue;
      }
      try {
        results.add(ExtractedTextFile(entry.name, _decodeText(Uint8List.fromList(data))));
        totalBytes += data.length;
      } catch (_) {
        skippedCount++; // binary or undecodable — skip quietly
      }
    }

    if (results.isEmpty) {
      throw FormatException(
          'No text/code files found inside "$zipName" (everything was binary, too large, or an unrecognized type).');
    }
    if (skippedCount > 0) {
      results.add(ExtractedTextFile(
        '_note.txt',
        '($skippedCount file(s) inside the zip were skipped: binary, too large, or an unrecognized type.)',
      ));
    }
    return results;
  }

  static String _decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      // Fall back for files with an odd encoding — good enough for a
      // preview even if a few characters look off, rather than crashing.
      return latin1.decode(bytes);
    }
  }
}
