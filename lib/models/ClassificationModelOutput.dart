class ClassificationModelOutput {
  final String dishName;
  final double confidence;
  final String servingSize;
  ClassificationModelOutput({
    required this.dishName,
    required this.confidence,
    required this.servingSize,
  });
}
