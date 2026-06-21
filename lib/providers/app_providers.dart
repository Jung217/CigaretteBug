import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/smoking_record.dart';
import '../services/brand_database.dart';
import '../services/record_storage.dart';

enum TimeRange { day, week, month, year }

// Brand database provider
final brandDatabaseProvider = Provider<BrandDatabase>((ref) => BrandDatabase());

// Record storage provider
final recordStorageProvider = Provider<RecordStorage>((ref) => RecordStorage());

// Time range selection
final timeRangeProvider = StateProvider<TimeRange>((ref) => TimeRange.week);

// Current date offset (for navigating between periods)
final dateOffsetProvider = StateProvider<int>((ref) => 0);

// All records notifier
final recordsProvider = StateNotifierProvider<RecordsNotifier, List<SmokingRecord>>((ref) {
  return RecordsNotifier(ref.read(recordStorageProvider));
});

class RecordsNotifier extends StateNotifier<List<SmokingRecord>> {
  final RecordStorage _storage;

  RecordsNotifier(this._storage) : super([]);

  Future<void> load() async {
    await _storage.load();
    state = _storage.allRecords;
  }

  Future<void> addRecord(SmokingRecord record) async {
    await _storage.addRecord(record);
    state = _storage.allRecords;
  }

  Future<void> deleteRecord(String id) async {
    await _storage.deleteRecord(id);
    state = _storage.allRecords;
  }
}

// ── Period helpers (shared by the home pile and the stats screen) ──

/// [start, end) bounds for a time range at a given offset (0 = current).
(DateTime, DateTime) periodBounds(TimeRange range, int offset,
    [DateTime? nowOverride]) {
  final now = nowOverride ?? DateTime.now();
  switch (range) {
    case TimeRange.day:
      final day = now.add(Duration(days: offset));
      final start = DateTime(day.year, day.month, day.day);
      return (start, start.add(const Duration(days: 1)));
    case TimeRange.week:
      final weekStart = now.add(Duration(days: offset * 7));
      final monday = weekStart.subtract(Duration(days: weekStart.weekday - 1));
      final start = DateTime(monday.year, monday.month, monday.day);
      return (start, start.add(const Duration(days: 7)));
    case TimeRange.month:
      final targetMonth = DateTime(now.year, now.month + offset, 1);
      return (targetMonth, DateTime(targetMonth.year, targetMonth.month + 1, 1));
    case TimeRange.year:
      final targetYear = DateTime(now.year + offset, 1, 1);
      return (targetYear, DateTime(targetYear.year + 1, 1, 1));
  }
}

/// Records falling within the given range/offset window.
List<SmokingRecord> recordsForPeriod(
    List<SmokingRecord> all, TimeRange range, int offset) {
  final (start, end) = periodBounds(range, offset);
  return all
      .where((r) => !r.createdAt.isBefore(start) && r.createdAt.isBefore(end))
      .toList();
}

// Filtered records based on the selected time range + offset.
final filteredRecordsProvider = Provider<List<SmokingRecord>>((ref) {
  final records = ref.watch(recordsProvider);
  final range = ref.watch(timeRangeProvider);
  final offset = ref.watch(dateOffsetProvider);
  return recordsForPeriod(records, range, offset);
});

// Settings
final cigaretteButtModeProvider = StateProvider<bool>((ref) => false);
final buttIntervalMinutesProvider = StateProvider<int>((ref) => 30);
