// lib/logic/DishClassification.dart
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle; // لاستخدام rootBundle لقراءة الملف
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/ClassificationModelInput.dart'; // تأكد من المسار الصحيح
import '../models/ClassificationModelOutput.dart'; // تأكد من المسار الصحيح
import '../utils/constants.dart'; // تأكد من المسار الصحيح

class DishClassification {
  Interpreter? _interpreter;
  List<String>? _labels;

  DishClassification() {
    _loadModel();
    _loadLabels();
  }

  Future<void> _loadModel() async {
    try {
      // تخصيص خيارات للمترجم (اختياري, يمكن إضافة تسريع GPU هنا)
      final interpreterOptions = InterpreterOptions();

      _interpreter = await Interpreter.fromAsset(
        AppConstants.classificationModelPath,
        options: interpreterOptions,
      );
      log('Classification model loaded successfully.');
      // طباعة تفاصيل المدخلات والمخرجات للتحقق
      log('Input tensor details: ${_interpreter?.getInputTensors()}');
      log('Output tensor details: ${_interpreter?.getOutputTensors()}');
    } catch (e) {
      log('Error loading classification model: $e');
    }
  }

  Future<void> _loadLabels() async {
    try {
      final labelsData = await rootBundle.loadString(AppConstants.classificationLabelsPath);
      _labels = labelsData.split('\n').map((label) => label.trim()).where((label) => label.isNotEmpty).toList();
      log('Classification labels loaded successfully. Count: ${_labels?.length}');
      if (_labels != null && _labels!.length != 101) {
        log('Warning: Expected 101 labels, but found ${_labels!.length}');
      }
    } catch (e) {
      log('Error loading classification labels: $e');
    }
  }

  Future<ClassificationModelOutput> classifyDish(ClassificationModelInput input) async {
    if (_interpreter == null || _labels == null) {
      log('Error: Classification model or labels not loaded.');
      // يمكنك إرجاع خطأ أو قيمة افتراضية
      return ClassificationModelOutput(dishName: 'Error: Model not ready', confidence: 0.0, servingSize: ''); // اضف servingSize اذا كانت موجودة
    }

    try {
      // تجهيز بيانات الإدخال
      // الشكل المطلوب [1, 250, 250, 3]
      // الكلاس يتوقع List<double>, نحول Float32List إليها
      var inputList = Float32List.fromList(input.imageData);
      // نتأكد من حجم المدخلات
      int expectedInputSize = 1 * AppConstants.classificationInputSize * AppConstants.classificationInputSize * 3;
      if (inputList.length != expectedInputSize) {
        log('Error: Classification input data size mismatch! Expected ${expectedInputSize}, got ${inputList.length}');
        throw Exception('Input size mismatch');
      }
      var inputTensor = [inputList.buffer.asFloat32List().reshape([1, AppConstants.classificationInputSize, AppConstants.classificationInputSize, 3])];


      // تجهيز بيانات الإخراج
      // الشكل المتوقع [1, 101] (بناءً على الكود السابق)
      var outputTensor = List.filled(1 * 101, 0.0).reshape([1, 101]); // 101 فئة

      log('Running classification inference...');
      // تشغيل النموذج
      _interpreter!.run(inputTensor[0], outputTensor);
      log('Classification inference completed.');

      // معالجة المخرجات
      List<double> outputList = outputTensor[0].cast<double>();
      int bestIndex = 0;
      double maxConfidence = 0.0;

      for (int i = 0; i < outputList.length; i++) {
        if (outputList[i] > maxConfidence) {
          maxConfidence = outputList[i];
          bestIndex = i;
        }
      }

      // التحقق من أن الفهرس ضمن حدود قائمة التسميات
      if (bestIndex >= 0 && bestIndex < _labels!.length) {
        String predictedLabel = _labels![bestIndex];
        log('Classification result: Label=$predictedLabel, Confidence=$maxConfidence, Index=$bestIndex');
        return ClassificationModelOutput(
            dishName: predictedLabel,
            confidence: maxConfidence,
            servingSize: '' // اضف servingSize اذا كانت موجودة
        );
      } else {
        log('Error: Best index ($bestIndex) is out of bounds for labels list (size: ${_labels!.length}).');
        return ClassificationModelOutput(dishName: 'Error: Index out of bounds', confidence: 0.0, servingSize: '');
      }
    } catch (e) {
      log('Error during classification inference: $e');
      return ClassificationModelOutput(dishName: 'Error: Inference failed', confidence: 0.0, servingSize: '');
    }
  }

  // يمكنك إضافة دالة لتحرير الموارد عند عدم الحاجة للكلاس
  void close() {
    _interpreter?.close();
    log('Classification interpreter closed.');
  }
}