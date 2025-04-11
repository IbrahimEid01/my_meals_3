// lib/screens/ResultsScreen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:my_meals_3/utils/constants.dart'; // لاستخدام الألوان

// تم تعديل لاستقبال البيانات الخمسة
class ResultsScreen extends StatelessWidget {
  final File imageFile;
  final String foodClass;
  final double confidence;
  final double calories;
  final double mass;
  final double fat;
  final double carbs;
  final double protein;

  const ResultsScreen({
    Key? key,
    required this.imageFile,
    required this.foodClass,
    required this.confidence,
    required this.calories,
    required this.mass,
    required this.fat,
    required this.carbs,
    required this.protein,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Analysis Results for $foodClass'),
        backgroundColor: AppConstants.primaryColor,
        centerTitle: true,
      ),
      body: SingleChildScrollView( // للسماح بالتمرير إذا كانت المحتويات كثيرة
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // تمديد العناصر الأفقية
          children: [
            // عرض الصورة
            ClipRRect( // لجعل الحواف دائرية
              borderRadius: BorderRadius.circular(12.0),
              child: Image.file(
                imageFile,
                height: 250, // ارتفاع مناسب للصورة
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 20),

            // عرض اسم الطبق ومستوى الثقة
            Card( // استخدام Card لتحسين المظهر
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      foodClass,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppConstants.primaryColor),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // عرض المعلومات الغذائية
            _buildNutritionCard(context), // استدعاء دالة بناء كارت التغذية

            const SizedBox(height: 30),
            // زر للعودة للشاشة الرئيسية أو للكاميرا
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 15)
              ),
              onPressed: () {
                // يمكنك تحديد إلى أين يعود المستخدم
                // Navigator.pop(context); // للعودة للكاميرا
                Navigator.of(context).popUntil((route) => route.isFirst); // للعودة للشاشة الرئيسية
              },
              child: const Text('Done', style: TextStyle(fontSize: 18, color: Colors.white)),
            )

          ],
        ),
      ),
    );
  }

  // دالة مساعدة لبناء كارت المعلومات الغذائية
  Widget _buildNutritionCard(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nutritional Information',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppConstants.primaryColor),
            ),
            const SizedBox(height: 15),
            _buildNutritionRow('Serving Size (Mass)', mass, 'g'), // عرض الكتلة كحجم الوجبة
            const Divider(),
            _buildNutritionRow('Calories', calories, 'kcal'),
            const Divider(),
            _buildNutritionRow('Protein', protein, 'g'),
            const Divider(),
            _buildNutritionRow('Fat', fat, 'g'),
            const Divider(),
            _buildNutritionRow('Carbohydrates', carbs, 'g'),
          ],
        ),
      ),
    );
  }

  // دالة مساعدة لبناء صف في جدول المعلومات الغذائية
  Widget _buildNutritionRow(String label, double value, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          // عرض القيمة مقربة ومنسقة
          Text(
            // التعامل مع القيم التي قد تكون صغيرة جداً أو صفر
            value.isNaN || value.isInfinite || value < 0.01 ? 'N/A' : '${value.toStringAsFixed(1)} $unit',
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

// تأكد من أن لديك كلاس HistoryEntry يحتوي على الحقول الخمسة
// مثال في ملف HistoryStorage.dart أو ملف منفصل:
/*

*/