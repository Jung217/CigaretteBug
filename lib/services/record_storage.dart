import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/smoking_record.dart';

/// Local persistence for smoking records.
///
/// Hardened over the original prototype:
/// • atomic writes (temp file + rename) so a crash mid-write can't truncate
///   the whole history,
/// • a versioned wrapper ({"version":1,"records":[...]}) with backward
///   compatibility for the old bare-array format,
/// • on a parse failure the corrupt file is backed up to *.corrupt instead of
///   being silently wiped, so the user's data is recoverable.
class RecordStorage {
  static final RecordStorage _instance = RecordStorage._();
  factory RecordStorage() => _instance;
  RecordStorage._();

  static const int _schemaVersion = 1;

  List<SmokingRecord> _records = [];
  bool _loaded = false;

  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/smoking_records.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _file;
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final decoded = json.decode(jsonStr);
        // Support both the new versioned wrapper and the legacy bare array.
        final List list = decoded is List
            ? decoded
            : (decoded['records'] as List? ?? const []);
        _records = list
            .map((e) => SmokingRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      // NEVER silently destroy the user's history. Preserve the unreadable
      // file as a backup so it can be recovered, then start empty in memory.
      await _backupCorruptFile();
      _records = [];
    }
    _loaded = true;
  }

  Future<void> _backupCorruptFile() async {
    try {
      final file = await _file;
      if (await file.exists()) {
        await file.copy('${file.path}.corrupt');
      }
    } catch (_) {
      // best-effort; nothing more we can do safely
    }
  }

  Future<void> _save() async {
    final file = await _file;
    final jsonStr = json.encode({
      'version': _schemaVersion,
      'records': _records.map((r) => r.toJson()).toList(),
    });
    // Atomic write: write to a temp file, then rename over the target.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonStr, flush: true);
    await tmp.rename(file.path);
  }

  List<SmokingRecord> get allRecords => List.unmodifiable(_records);

  Future<void> addRecord(SmokingRecord record) async {
    _records.add(record);
    await _save();
  }

  Future<void> deleteRecord(String id) async {
    _records.removeWhere((r) => r.id == id);
    await _save();
  }

  List<SmokingRecord> getRecordsInRange(DateTime start, DateTime end) {
    return _records.where((r) =>
      r.createdAt.isAfter(start) && r.createdAt.isBefore(end)
    ).toList();
  }

  SmokingRecord? get lastRecord {
    if (_records.isEmpty) return null;
    return _records.reduce((a, b) =>
      a.createdAt.isAfter(b.createdAt) ? a : b
    );
  }
}
