
class HistoryEntry {
  final String imagePath;    // مسار الصورة
  final String dishName;     // اسم الطبق المصنف
  final double confidence;   // نسبة الثقة
  final String servingSize;  // حجم الوجبة
  final DateTime dateTime;   // وقت الالتقاط

  HistoryEntry({
    required this.imagePath,
    required this.dishName,
    required this.confidence,
    required this.servingSize,
    required this.dateTime,
  });

  Map<String, dynamic> toJson() => {
    'imagePath': imagePath,
    'dishName': dishName,
    'confidence': confidence,
    'servingSize': servingSize,
    'dateTime': dateTime.toIso8601String(),
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      imagePath: json['imagePath'],
      dishName: json['dishName'],
      confidence: (json['confidence'] as num).toDouble(),
      servingSize: json['servingSize'],
      dateTime: DateTime.parse(json['dateTime']),
    );
  }
}
