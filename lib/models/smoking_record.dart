import 'package:uuid/uuid.dart';

class SmokingRecord {
  final String id;
  final String brandBarcode;
  final DateTime createdAt;
  final String? groupId;

  SmokingRecord({
    String? id,
    required this.brandBarcode,
    DateTime? createdAt,
    this.groupId,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  double get agingProgress {
    final hours = DateTime.now().difference(createdAt).inHours;
    if (hours < 6) return 0.0;
    if (hours < 24) return 0.2;
    if (hours < 72) return 0.4;
    if (hours < 168) return 0.7;
    return 1.0;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'brandBarcode': brandBarcode,
    'createdAt': createdAt.toIso8601String(),
    'groupId': groupId,
  };

  factory SmokingRecord.fromJson(Map<String, dynamic> json) {
    return SmokingRecord(
      id: json['id'] as String,
      brandBarcode: json['brandBarcode'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      groupId: json['groupId'] as String?,
    );
  }
}
