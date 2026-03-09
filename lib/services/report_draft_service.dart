import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ReportDraftService {
  static const String _fileName = 'report_drafts.json';

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<Map<String, dynamic>>> getDrafts() async {
    final file = await _getFile();
    if (!await file.exists()) {
      return [];
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return [];
    }
    return decoded
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<void> saveDraft(Map<String, dynamic> draft) async {
    final current = await getDrafts();
    final localId = (draft['localId'] ?? '').toString().trim();
    if (localId.isEmpty) {
      current.add(draft);
      await _writeAll(current);
      return;
    }

    final index = current.indexWhere(
      (item) => (item['localId'] ?? '').toString().trim() == localId,
    );
    if (index >= 0) {
      current[index] = draft;
    } else {
      current.add(draft);
    }
    await _writeAll(current);
  }

  Future<void> removeDraft(String localId) async {
    final current = await getDrafts();
    current.removeWhere((e) => e['localId'] == localId);
    await _writeAll(current);
  }

  Future<void> _writeAll(List<Map<String, dynamic>> drafts) async {
    final file = await _getFile();
    await file.writeAsString(jsonEncode(drafts));
  }
}
