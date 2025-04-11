// lib/models/NutritionModelOutput.dart
class NutritionModelOutput {
  final double calories;
  final double mass; // تمت إضافته
  final double fat;
  final double carbs;
  final double protein;

  NutritionModelOutput({
    required this.calories,
    required this.mass,
    required this.fat,
    required this.carbs,
    required this.protein,
  });
}