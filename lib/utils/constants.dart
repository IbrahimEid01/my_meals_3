// lib/utils/constants.dart
import 'package:flutter/material.dart';

class AppConstants {
  // أبعاد مدخلات النماذج (تم التحديث)
  static const int classificationInputSize = 250;
  static const int nutritionInputSize = 224;
  static const int segmentationInputSize = 257; // إذا كنت ستستخدم DeepLabV3 لاحقًا

  // مسارات النماذج وملف التسميات (تأكد من تطابقها مع مجلداتك)
  static const String classificationModelPath = 'assets/models2/classification_model.tflite';
  static const String nutritionModelPath = 'assets/models2/nutrition_model.tflite';
  static const String segmentationModelPath = 'assets/models2/DeepLabV3.tflite';
  static const String classificationLabelsPath = 'assets/raw/c1_classes.txt'; // تأكد من وجوده في هذا المسار

  // عامل التطبيع (كما كان)
  static const double normalizationFactor = 255.0;

  // ثوابت فك التطبيع لنموذج التغذية (5 قيم بالترتيب: سعرات، كتلة، دهون، كربوهيدرات، بروتين)
  // تأكد من صحة هذه القيم لنموذجك!
  static const double unNormCaloriesFactor = 9485.8154296875;
  static const double unNormMassFactor = 7975.0;
  static const double unNormFatFactor = 875.541015625;
  static const double unNormCarbsFactor = 844.568603515625;
  static const double unNormProteinFactor = 147.491821;


  static const int segmentationFoodClassIndex = 151; // تأكد من صحة هذا الفهرس لنموذجك!
  // ألوان أو ثوابت أخرى للتطبيق
  static const Color primaryColor = Colors.teal; // مثال


  // ثوابت SharedPreferences (تمت إضافتها)
  static const String prefLanguageKey = 'pref_language';
  static const String prefDataSourceKey = 'pref_data_source';

}
