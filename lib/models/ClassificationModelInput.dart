class ClassificationModelInput {
  final List<double> imageData; // مصفوفة من القيم [R, G, B] مطبّعة (0..1)

  ClassificationModelInput({required this.imageData});
}
