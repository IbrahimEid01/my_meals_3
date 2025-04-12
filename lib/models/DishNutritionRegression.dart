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
      // تجهيز بيانات الإدخال: الشكل المطلوب [1, 224, 224, 3]
      var inputList = Float32List.fromList(input.imageData);
      int expectedInputSize = 1 * AppConstants.nutritionInputSize * AppConstants.nutritionInputSize * 3;
      if (inputList.length != expectedInputSize) {
        log('Error: Nutrition input data size mismatch! Expected $expectedInputSize, got ${inputList.length}');
        throw Exception('Input size mismatch');
      }
      final inputBuffer = inputList.buffer.asFloat32List().reshape(
        [1, AppConstants.nutritionInputSize, AppConstants.nutritionInputSize, 3],
      );

      // استخراج أبعاد المخرج من النموذج
      List<int> outputShape = _interpreter!.getOutputTensors()[0].shape;
      int outputSize = outputShape.reduce((a, b) => a * b);
      if (outputShape.length != 2 || outputShape[0] != 1 || outputShape[1] != 5) {
        log('Error: Expected output shape [1,5] but got $outputShape.');
        throw Exception('Output shape mismatch');
      }
      // تخصيص مخزن للمخرجات بناءً على الحجم المستخلص (يجب أن يكون 5)
      Float32List outputBuffer = Float32List(outputSize);

      log('Running nutrition inference with output shape: $outputShape...');
      _interpreter!.run(inputBuffer, outputBuffer);
      log('Nutrition inference completed.');

      // استخراج القيم من outputBuffer (افتراض أن النتيجة هي [1,5])
      double rawCalories = outputBuffer[0];
      double rawMass = outputBuffer[1];
      double rawFat = outputBuffer[2];
      double rawCarbs = outputBuffer[3];
      double rawProtein = outputBuffer[4];

      log('Raw model outputs: Cal=${rawCalories.toStringAsFixed(4)}, Mass=${rawMass.toStringAsFixed(4)}, Fat=${rawFat.toStringAsFixed(4)}, Carbs=${rawCarbs.toStringAsFixed(4)}, Protein=${rawProtein.toStringAsFixed(4)}');

      double unNormCalories = (rawCalories * AppConstants.unNormCaloriesFactor).abs();
      double unNormMass = (rawMass * AppConstants.unNormMassFactor).abs();
      double unNormFat = (rawFat * AppConstants.unNormFatFactor).abs();
      double unNormCarbs = (rawCarbs * AppConstants.unNormCarbsFactor).abs();
      double unNormProtein = (rawProtein * AppConstants.unNormProteinFactor).abs();

      log('Un-normalized outputs: Cal=${unNormCalories.toStringAsFixed(2)}, Mass=${unNormMass.toStringAsFixed(2)}g, Fat=${unNormFat.toStringAsFixed(2)}g, Carbs=${unNormCarbs.toStringAsFixed(2)}g, Protein=${unNormProtein.toStringAsFixed(2)}g');

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