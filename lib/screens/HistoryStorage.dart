// lib/utils/HistoryStorage.dart
import 'dart:convert';
import 'dart:developer'; // لاستخدام log
import 'package:shared_preferences/shared_preferences.dart';
import '../models/HistoryEntry.dart';


// --- تأكد من أن لديك تعريف لكلاس HistoryEntry هنا أو تم استيراده ---
// --- يجب أن يحتوي على الحقول الخمسة للتغذية + mass ---
// class HistoryEntry {
//   final String imagePath;
//   final String dishName;
//   final double confidence;
//   final double calories;
//   final double mass;
//   final double fat;
//   final double carbs;
//   final double protein;
//   final String servingSize; // يمكنك إزالته إذا لم تعد تحتاجه منفصلاً
//   final DateTime dateTime;
//
//   HistoryEntry({
//     required this.imagePath,
//     required this.dishName,
//     required this.confidence,
//     required this.calories,
//     required this.mass,
//     required this.fat,
//     required this.carbs,
//     required this.protein,
//     required this.servingSize, // قد يكون '${mass.toStringAsFixed(1)} g'
//     required this.dateTime,
//   });
//
//   Map<String, dynamic> toJson() => {
//     'imagePath': imagePath,
//     'dishName': dishName,
//     'confidence': confidence,
//     'calories': calories,
//     'mass': mass,
//     'fat': fat,
//     'carbs': carbs,
//     'protein': protein,
//     'servingSize': servingSize,
//     'dateTime': dateTime.toIso8601String(),
//   };
//
//   factory HistoryEntry.fromJson(Map<String, dynamic> json) {
//     // إضافة قيم افتراضية للحقول الجديدة عند القراءة من بيانات قديمة قد لا تحتويها
//     return HistoryEntry(
//       imagePath: json['imagePath'] ?? 'unknown_path',
//       dishName: json['dishName'] ?? 'Unknown Dish',
//       confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
//       calories: (json['calories'] as num?)?.toDouble() ?? 0.0,
//       mass: (json['mass'] as num?)?.toDouble() ?? 0.0, // قيمة افتراضية
//       fat: (json['fat'] as num?)?.toDouble() ?? 0.0,     // قيمة افتراضية
//       carbs: (json['carbs'] as num?)?.toDouble() ?? 0.0,   // قيمة افتراضية
//       protein: (json['protein'] as num?)?.toDouble() ?? 0.0, // قيمة افتراضية
//       servingSize: json['servingSize'] ?? 'N/A',
//       dateTime: DateTime.tryParse(json['dateTime'] ?? '') ?? DateTime.now(),
//     );
//   }
// }
// --- نهاية تعريف HistoryEntry ---


class HistoryStorage {
  static const String _historyKey = 'meal_history';

  static Future<void> saveHistory(List<HistoryEntry> history) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // تحويل قائمة الكائنات إلى قائمة من JSON strings
      List<String> historyJson = history.map((entry) => jsonEncode(entry.toJson())).toList();
      await prefs.setStringList(_historyKey, historyJson);
      log('History saved successfully. Entries: ${history.length}');
    } catch (e) {
      log('Error saving history: $e');
    }
  }

  static Future<List<HistoryEntry>> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? historyJson = prefs.getStringList(_historyKey);

      if (historyJson == null) {
        log('No history found.');
        return []; // إرجاع قائمة فارغة إذا لم يكن هناك سجل
      }

      // تحويل قائمة JSON strings إلى قائمة من كائنات HistoryEntry
      List<HistoryEntry> history = historyJson.map((entryJson) {
        try {
          return HistoryEntry.fromJson(jsonDecode(entryJson));
        } catch(e) {
          log("Error decoding history entry: $entryJson, Error: $e");
          return null; // تجاهل الإدخال غير الصالح
        }
      }).whereType<HistoryEntry>().toList(); // إزالة القيم null
      log('History loaded successfully. Entries: ${history.length}');
      return history;
    } catch (e) {
      log('Error loading history: $e');
      return []; // إرجاع قائمة فارغة في حالة حدوث خطأ
    }
  }

  static Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
      log('History cleared successfully.');
    } catch (e) {
      log('Error clearing history: $e');
    }
  }
}