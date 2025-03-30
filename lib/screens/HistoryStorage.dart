import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'history_data.dart';

class HistoryStorage {
  static const String _key = 'history_entries';

  /// حفظ قائمة السجل في SharedPreferences
  static Future<void> saveHistory(List<HistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> jsonList =
    entries.map((entry) => jsonEncode(entry.toJson())).toList();
    await prefs.setStringList(_key, jsonList);
  }

  /// استرجاع قائمة السجل من SharedPreferences
  static Future<List<HistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? jsonList = prefs.getStringList(_key);
    if (jsonList == null) return [];
    return jsonList
        .map((jsonString) =>
        HistoryEntry.fromJson(jsonDecode(jsonString) as Map<String, dynamic>))
        .toList();
  }
}
