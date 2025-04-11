// lib/models/HistoryEntry.dart
class HistoryEntry {
  final String imagePath;
  final String dishName;
  final double confidence;
  final double calories;
  final double mass;
  final double fat;
  final double carbs;
  final double protein;
  final String servingSize;
  final DateTime dateTime;

  HistoryEntry({
    required this.imagePath,
    required this.dishName,
    required this.confidence,
    required this.calories,
    required this.mass,
    required this.fat,
    required this.carbs,
    required this.protein,
    required this.servingSize,
    required this.dateTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'imagePath': imagePath,
      'dishName': dishName,
      'confidence': confidence,
      'calories': calories,
      'mass': mass,
      'fat': fat,
      'carbs': carbs,
      'protein': protein,
      'servingSize': servingSize,
      'dateTime': dateTime.toIso8601String(),
    };
  }

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      imagePath: json['imagePath'] ?? 'unknown_path',
      dishName: json['dishName'] ?? 'Unknown Dish',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      calories: (json['calories'] as num?)?.toDouble() ?? 0.0,
      mass: (json['mass'] as num?)?.toDouble() ?? 0.0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0.0,
      carbs: (json['carbs'] as num?)?.toDouble() ?? 0.0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0.0,
      servingSize: json['servingSize'] ?? 'N/A',
      dateTime: DateTime.tryParse(json['dateTime'] ?? '') ?? DateTime.now(),
    );
  }
}