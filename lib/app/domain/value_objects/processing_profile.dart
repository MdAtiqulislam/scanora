import 'dart:convert';

import '../enums/scan_enums.dart';
import 'processing_adjustments.dart';

class ProcessingProfile {
  final ScanFilterType filterType;
  final ProcessingAdjustments adjustments;
  final Map<String, double> parameters;

  const ProcessingProfile({
    this.filterType = ScanFilterType.original,
    this.adjustments = const ProcessingAdjustments(),
    this.parameters = const {},
  });

  Map<String, dynamic> toMap() {
    final keys = parameters.keys.toList()..sort();
    return {
      'filterType': filterType.name,
      'adjustments': adjustments.toMap(),
      'parameters': {for (final key in keys) key: parameters[key]},
    };
  }

  factory ProcessingProfile.fromMap(Map<String, dynamic> map) {
    final name = map['filterType'] as String?;
    final filter = ScanFilterType.values.where((value) => value.name == name);
    return ProcessingProfile(
      filterType: filter.isEmpty ? ScanFilterType.original : filter.first,
      adjustments: ProcessingAdjustments.fromMap(
        (map['adjustments'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      parameters: ((map['parameters'] as Map?) ?? const {}).map(
        (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
      ),
    );
  }

  String canonicalJson() {
    final sorted = parameters.keys.toList()..sort();
    return '{"adjustments":${jsonEncode(adjustments.toMap())},'
        '"filterType":"${filterType.name}","parameters":'
        '${jsonEncode({for (final key in sorted) key: parameters[key]})}}';
  }

  @override
  bool operator ==(Object other) =>
      other is ProcessingProfile && other.canonicalJson() == canonicalJson();

  @override
  int get hashCode => canonicalJson().hashCode;
}
