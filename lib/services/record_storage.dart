import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/smoking_record.dart';

class RecordStorage {
  static final RecordStorage _instance = RecordStorage._();
  factory RecordStorage() => _instance;
  RecordStorage._();

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
        final list = json.decode(jsonStr) as List;
        _records = list
            .map((e) => SmokingRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      _records = [];
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final file = await _file;
    final jsonStr = json.encode(_records.map((r) => r.toJson()).toList());
    await file.writeAsString(jsonStr);
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
