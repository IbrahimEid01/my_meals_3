import 'dart:io';
import 'package:flutter/material.dart';

class ResultsScreen extends StatelessWidget {
  final File imageFile;
  final String foodClass;
  final String servingSize;
  final double confidence;
  final Map<String, dynamic>? nutritionData;

  const ResultsScreen({
    Key? key,
    required this.imageFile,
    required this.foodClass,
    required this.servingSize,
    required this.confidence,
    required this.nutritionData,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نتائج التعرف'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Image.file(imageFile),
            const SizedBox(height: 20),
            Text(
              'نوع الطعام: $foodClass',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              'حجم الوجبة: $servingSize',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              'نسبة الثقة: ${(confidence * 100).toStringAsFixed(2)}%',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            nutritionData != null
                ? buildNutritionInfo(nutritionData!)
                : const Text('لا توجد بيانات غذائية متاحة'),
          ],
        ),
      ),
    );
  }

  Widget buildNutritionInfo(Map<String, dynamic> data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'المعلومات الغذائية:',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text('السعرات الحرارية: ${data['calories_per_100g']} لكل 100 جرام'),
        Text('البروتين: ${data['protein_g_per_100g']} جرام لكل 100 جرام'),
        Text('الدهون: ${data['fats_g_per_100g']} جرام لكل 100 جرام'),
        Text('الكربوهيدرات: ${data['carbs_g_per_100g']} جرام لكل 100 جرام'),
        Text('الألياف: ${data['fiber_g_per_100g']} جرام لكل 100 جرام'),
        // يمكنك إضافة حقول أخرى إذا توفرت
      ],
    );
  }
}
