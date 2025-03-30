class NutritionModelOutput {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double? fiber; // إذا كان موجوداً
  NutritionModelOutput({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.fiber,
  });
}
