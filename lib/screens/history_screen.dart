import 'package:flutter/material.dart';
import 'dart:io';
import 'HistoryStorage.dart';
import 'history_data.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final entries = await HistoryStorage.loadHistory();
    setState(() {
      _entries = entries.reversed.toList(); // عرض الأحدث أولاً
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الصور'),
      ),
      body: _entries.isEmpty
          ? const Center(child: Text('لا توجد صور في السجل بعد'))
          : ListView.builder(
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return ListTile(
            leading: Image.file(
              File(entry.imagePath),
              width: 50,
              height: 50,
              fit: BoxFit.cover,
            ),
            title: Text(entry.dishName),
            subtitle: Text(
                'الثقة: ${(entry.confidence * 100).toStringAsFixed(1)}% - ${entry.servingSize}\n${entry.dateTime.toLocal()}'),
            onTap: () {
              // يمكنك هنا إضافة شاشة تفاصيل إذا أردت
            },
          );
        },
      ),
    );
  }
}
