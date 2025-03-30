class AppConstants {
  // أبعاد الصورة المطلوبة للنموذج
  static const int inputImageWidth = 300;
  static const int inputImageHeight = 300;
  // معامل التطبيع (لتحويل قيم 0-255 إلى 0-1)
  static const double normalizationFactor = 255.0;

  // مسارات ملفات النموذج وملفات التصنيفات (يجب تعديلها وفقًا لمشروعك)
  static const String classificationModelPath = 'assets/models2/classification_model.tflite';
  static const String nutritionModelPath = 'assets/models2/nutrition_model.tflite';
  static const String classesFilePath = 'assets/raw/c1_classes.txt';

  // معامل آخر إن احتجت (مثلاً عتبة segmentation)
  static const double segmentationThreshold = 0.5;

  static const String prefLanguageKey = 'language';
  static const String prefDataSourceKey = 'dataSource';

}
