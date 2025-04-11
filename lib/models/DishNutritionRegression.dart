// lib/logic/DishNutritionRegression.dart
import 'dart:developer';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/NutritionModelInput.dart';
import '../models/NutritionModelOutput.dart';
import '../utils/constants.dart';
import 'dart:math' hide log;

class DishNutritionRegression {
  Interpreter? _interpreter;

  DishNutritionRegression() {
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      final interpreterOptions = InterpreterOptions();
      _interpreter = await Interpreter.fromAsset(
        AppConstants.nutritionModelPath,
        options: interpreterOptions,
      );
      log('Nutrition model loaded successfully.');
      log('Input tensor details: ${_interpreter?.getInputTensors()}');
      log('Output tensor details: ${_interpreter?.getOutputTensors()}');

      // التحقق من عدد المخرجات (يفترض 5 مخرجات)
      if (_interpreter?.getOutputTensors().length != 5) {
        log('Warning: Expected 5 output tensors for nutrition model, but found ${_interpreter?.getOutputTensors().length}');
      }
    } catch (e) {
      log('Error loading nutrition model: $e');
    }
  }

  Future<NutritionModelOutput> predictNutrition(NutritionModelInput input) async {
    if (_interpreter == null) {
      log('Error: Nutrition model not loaded.');
      return NutritionModelOutput(calories: 0.0, mass: 0.0, fat: 0.0, carbs: 0.0, protein: 0.0);
    }

    try {
      // تجهيز بيانات الإدخال:
      // الشكل المطلوب هو [1, nutritionInputSize, nutritionInputSize, 3]
      var inputList = Float32List.fromList(input.imageData);
      int expectedInputSize = 1 * AppConstants.nutritionInputSize * AppConstants.nutritionInputSize * 3;
      if (inputList.length != expectedInputSize) {
        log('Error: Nutrition input data size mismatch! Expected $expectedInputSize, got ${inputList.length}');
        throw Exception('Input size mismatch');
      }

      // إعادة تشكيل البيانات لتصبح [1, nutritionInputSize, nutritionInputSize, 3]
      final inputBuffer = inputList.buffer.asFloat32List().reshape(
        [1, AppConstants.nutritionInputSize, AppConstants.nutritionInputSize, 3],
      );

      // تجهيز بيانات الإخراج: نموذج التغذية يُفترض أن يُخرج 5 قيم، كل منها [1,1]
      Float32List outputBuffer = Float32List(5);

      log('Running nutrition inference...');
      // تشغيل النموذج باستخدام run() العادية
      _interpreter!.run(inputBuffer, outputBuffer);
      log('Nutrition inference completed.');

      // استخراج القيم من outputBuffer
      double rawCalories = outputBuffer[0];
      double rawMass = outputBuffer[1];
      double rawFat = outputBuffer[2];
      double rawCarbs = outputBuffer[3];
      double rawProtein = outputBuffer[4];

      log('Raw model outputs: Cal=${rawCalories.toStringAsFixed(4)}, Mass=${rawMass.toStringAsFixed(4)}, Fat=${rawFat.toStringAsFixed(4)}, Carbs=${rawCarbs.toStringAsFixed(4)}, Prot=${rawProtein.toStringAsFixed(4)}');

      // فك التطبيع باستخدام الثوابت المعرفة (تأكد من صحة القيم مع بيانات التدريب)
      double unNormCalories = (rawCalories * AppConstants.unNormCaloriesFactor).abs();
      double unNormMass = (rawMass * AppConstants.unNormMassFactor).abs();
      double unNormFat = (rawFat * AppConstants.unNormFatFactor).abs();
      double unNormCarbs = (rawCarbs * AppConstants.unNormCarbsFactor).abs();
      double unNormProtein = (rawProtein * AppConstants.unNormProteinFactor).abs();

      log('Un-normalized outputs: Cal=${unNormCalories.toStringAsFixed(2)}, Mass=${unNormMass.toStringAsFixed(2)}g, Fat=${unNormFat.toStringAsFixed(2)}g, Carbs=${unNormCarbs.toStringAsFixed(2)}g, Prot=${unNormProtein.toStringAsFixed(2)}g');

      return NutritionModelOutput(
        calories: unNormCalories,
        mass: unNormMass,
        fat: unNormFat,
        carbs: unNormCarbs,
        protein: unNormProtein,
      );
    } catch (e) {
      log('Error during nutrition inference: $e');
      return NutritionModelOutput(calories: 0.0, mass: 0.0, fat: 0.0, carbs: 0.0, protein: 0.0);
    }
  }

  void close() {
    _interpreter?.close();
    log('Nutrition interpreter closed.');
  }
}


