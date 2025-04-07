// File: lib/utils/constants.dart
class AppConstants {
  // أبعاد الصورة المطلوبة لنماذج المعالجة
  // لنموذج التصنيف: 250x250 (يمكن تعديلها إذا تم تدريب النموذج على 300x300)
  static const int classificationInputWidth = 250;
  static const int classificationInputHeight = 250;

  // لنموذج التغذية: 224x224 (أو يمكن استخدام 300x300 بحسب التدريب)
  static const int nutritionInputWidth = 224;
  static const int nutritionInputHeight = 224;

  // أبعاد الصورة التي سيتم معالجتها في مرحلة DeepLabV3 (على سبيل المثال 257x257)
  static const int segmentationInputWidth = 257;
  static const int segmentationInputHeight = 257;

  // معامل التطبيع (لتحويل قيم 0-255 إلى 0-1)
  static const double normalizationFactor = 255.0;

  // مسارات ملفات النماذج وملفات التصنيفات
  static const String classificationModelPath = 'assets/models2/classification_model.tflite';
  static const String nutritionModelPath = 'assets/models2/nutrition_model.tflite';
  static const String segmentationModelPath = 'assets/models2/DeepLabV3.tflite';
  static const String classesFilePath = 'assets/raw/c1_classes.txt';

  // إعدادات أخرى (مثلاً عتبة segmentation)
  static const double segmentationThreshold = 0.5;

  // مفاتيح SharedPreferences للإعدادات
  static const String prefLanguageKey = 'language';
  static const String prefDataSourceKey = 'dataSource';
}