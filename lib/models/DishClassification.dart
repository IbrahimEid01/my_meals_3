import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/ClassificationModelInput.dart';
import '../models/ClassificationModelOutput.dart';

class DishClassification {
  Interpreter? _interpreter;
  List<String> _labels = [];

  // تحميل النموذج
  Future<void> loadModel() async {
    try {
      // يفترض وجود الملف في assets/ClassificationModel.tflite
      _interpreter = await Interpreter.fromAsset('assets/models2/classification_model.tflite');
      print('Classification Model loaded successfully');
    } catch (e) {
      print('Error loading classification model: $e');
    }
  }

  // تحميل التصنيفات (الليبلز)
  Future<void> loadLabels() async {
    try {
      // يفترض وجود الملف في assets/c1_classes.txt
      final labelTxt = await rootBundle.loadString('assets/raw/c1_classes.txt');
      _labels = labelTxt
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      print('Labels loaded successfully, count=${_labels.length}');
    } catch (e) {
      print('Error loading labels: $e');
    }
  }

  // دالة التصنيف الرئيسية
  Future<ClassificationModelOutput> classifyDish(ClassificationModelInput input) async {
    // إذا لم يكن النموذج أو الليبلز جاهزين، نحملهما
    if (_interpreter == null) {
      await loadModel();
    }
    if (_labels.isEmpty) {
      await loadLabels();
    }

    if (_interpreter == null || _labels.isEmpty) {
      throw Exception("Error: Model or labels not loaded in classifyDish");
    }

    try {
      // 1) تحويل List<double> إلى Float32List
      // نفترض شكل الإدخال [1, 300, 300, 3]
      // أي 300*300*3 = 270000 قيمة (لكل بكسل 3 قيم)
      final inputBuffer = Float32List.fromList(input.imageData).buffer;

      // 2) تجهيز مصفوفة الإخراج
      // نفترض عدد التصنيفات = عدد الأسطر في ملف _labels
      final outputBuffer = Float32List(_labels.length).buffer;

      // 3) تنفيذ الاستدلال
      _interpreter!.run(inputBuffer, outputBuffer);

      // 4) استخراج نتائج الإخراج وتحويلها إلى List<double>
      final output = outputBuffer.asFloat32List();

      // 5) إيجاد أعلى قيمة (confidence)
      int maxIndex = 0;
      double maxVal = output[0];
      for (int i = 1; i < output.length; i++) {
        if (output[i] > maxVal) {
          maxVal = output[i];
          maxIndex = i;
        }
      }

      // 6) إنشاء كائن المخرجات مع تمرير الحقول المطلوبة
      final dishName = (maxIndex < _labels.length) ? _labels[maxIndex] : 'Unknown';
      return ClassificationModelOutput(
        dishName: dishName,
        confidence: maxVal,
        servingSize: "غير متوفر", // أو يمكنك تعديلها حسب ما يعيده النموذج
      );
    } catch (e) {
      print('Error classifying dish: $e');
      return ClassificationModelOutput(
        dishName: "Unknown",
        confidence: 0.0,
        servingSize: "غير متوفر",
      );
    }
  }
}
