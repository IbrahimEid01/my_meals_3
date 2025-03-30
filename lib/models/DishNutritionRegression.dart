import 'dart:async';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/NutritionModelInput.dart';
import '../models/NutritionModelOutput.dart';


class DishNutritionRegression {
  Interpreter? _interpreter;

  Future<void> loadModel() async {
    try {
      // يفترض وجود الملف في assets/NutritionModel.tflite
      _interpreter = await Interpreter.fromAsset('assets/models2/nutrition_model.tflite');
      print('Nutrition Model loaded successfully');
    } catch (e) {
      print('Error loading Nutrition model: $e');
    }
  }

  Future<NutritionModelOutput> predictNutrition(NutritionModelInput input) async {
    if (_interpreter == null) {
      await loadModel();
    }
    if (_interpreter == null) {
      throw Exception("Error: Nutrition Model not loaded in predictNutrition");
    }

    try {
      // 1) تحويل List<double> إلى Float32List
      final inputBuffer = Float32List.fromList(input.imageData).buffer;

      // 2) نفترض أن الإخراج 4 قيم [السعرات, البروتين, الكربوهيدرات, الدهون]
      final outputBuffer = Float32List(4).buffer;

      // 3) تشغيل الاستدلال
      _interpreter!.run(inputBuffer, outputBuffer);

      // 4) استخراج القيم
      final output = outputBuffer.asFloat32List();
      return NutritionModelOutput(
        calories: output[0],
        protein: output[1],
        carbs: output[2],
        fat: output[3],
      );
    } catch (e) {
      print('Error predicting nutrition: $e');
      return NutritionModelOutput(
        calories: 0,
        protein: 0,
        carbs: 0,
        fat: 0,
      );
    }
  }
}
