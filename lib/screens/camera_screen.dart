// File: lib/screens/CustomCameraScreen.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
// استيراد النماذج والأدوات
import '../models/ClassificationModelInput.dart';
import '../models/NutritionModelInput.dart';
import '../models/DishClassification.dart';
import '../models/DishNutritionRegression.dart';
import '../utils/DeepLearning.dart';
// استيراد صفحة النتائج والسجل
import 'history_data.dart';
import 'results_screen.dart';
import 'HistoryStorage.dart';
import '../utils/constants.dart';




class CustomCameraScreen extends StatefulWidget {
  const CustomCameraScreen({Key? key}) : super(key: key);

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen> {
  late CameraController _cameraController;
  late Future<void> _initializeControllerFuture;
  final ImagePicker _picker = ImagePicker();

  File? _capturedImage;
  bool _isCapturing = false;
  bool _isFlashOn = false;
  File? _lastImageFile;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final firstCamera = cameras.first;
      _cameraController = CameraController(
        firstCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      _initializeControllerFuture = _cameraController.initialize();
      setState(() {});
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    try {
      _isFlashOn = !_isFlashOn;
      await _cameraController.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
      setState(() {});
    } catch (e) {
      print('Error toggling flash: $e');
    }
  }

  Future<void> _captureImage() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      await _initializeControllerFuture;
      final image = await _cameraController.takePicture();
      _capturedImage = File(image.path);
      _lastImageFile = _capturedImage;
      print("تم التقاط الصورة بنجاح. المسار: ${_capturedImage!.path}");
      setState(() {});
    } catch (e) {
      print('Error capturing image: $e');
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        _capturedImage = File(pickedFile.path);
        _lastImageFile = _capturedImage;
        print("تم اختيار الصورة من المعرض. المسار: ${_capturedImage!.path}");
        setState(() {});
      }
    } catch (e) {
      print('Error picking image: $e');
    }
  }

  void _discardImage() {
    setState(() {
      _capturedImage = null;
    });
  }

  /// دالة اقتصاص الصورة لتصبح مربعة (1:1)
  img.Image _cropToSquare(img.Image original) {
    int width = original.width;
    int height = original.height;
    if (width == height) return original;
    int size = width < height ? width : height;
    int xOffset = ((width - size) ~/ 2);
    int yOffset = ((height - size) ~/ 2);
    return img.copyCrop(
        original,
       x: xOffset,
       y: yOffset,
        width: size,
        height: size,
    );
  }

  Future<void> _processAndProceed() async {
    if (_capturedImage == null) return;
    try {
      final bytes = await _capturedImage!.readAsBytes();
      img.Image? decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) {
        throw Exception('Failed to decode image');
      }
      // قص الصورة لتصبح مربعة إذا لم تكن كذلك
      decodedImage = _cropToSquare(decodedImage);
      print("أبعاد الصورة بعد القص: ${decodedImage.width}x${decodedImage.height}");

      // تحويل الصورة إلى Float32List بناءً على أبعاد نموذج التصنيف (مثلاً 250x250)
      final floatListClassification = DeepLearning.loadImageAsFloatList(
          decodedImage, AppConstants.classificationInputWidth, AppConstants.classificationInputHeight);
      print("تم تحويل صورة التصنيف إلى Float32List.");

      // تحويل الصورة إلى Float32List بناءً على أبعاد نموذج التغذية (مثلاً 224x224)
      final floatListNutrition = DeepLearning.loadImageAsFloatList(
          decodedImage, AppConstants.nutritionInputWidth, AppConstants.nutritionInputHeight);
      print("تم تحويل صورة التغذية إلى Float32List.");

      // التصنيف
      final classificationInput = ClassificationModelInput(imageData: floatListClassification);
      final dishClassification = DishClassification();
      await dishClassification.loadModel();
      await dishClassification.loadLabels();
      final classificationOutput = await dishClassification.classifyDish(classificationInput);
      print("تم التصنيف: ${classificationOutput.dishName} بنسبة ثقة: ${classificationOutput.confidence}");

      // التحليل الغذائي
      final nutritionInput = NutritionModelInput(imageData: floatListNutrition);
      final dishNutritionRegression = DishNutritionRegression();
      await dishNutritionRegression.loadModel();
      final nutritionOutput = await dishNutritionRegression.predictNutrition(nutritionInput);
      print("تم التحليل الغذائي: السعرات الحرارية: ${nutritionOutput.calories}");

      // حفظ البيانات في السجل
      final newEntry = HistoryEntry(
        imagePath: _capturedImage!.path,
        dishName: classificationOutput.dishName,
        confidence: classificationOutput.confidence,
        servingSize: classificationOutput.servingSize,
        dateTime: DateTime.now(),
      );
      List<HistoryEntry> historyEntries = await HistoryStorage.loadHistory();
      historyEntries.add(newEntry);
      await HistoryStorage.saveHistory(historyEntries);
      print("تم حفظ بيانات الوجبة في السجل.");

      // الانتقال إلى شاشة النتائج
      final Map<String, dynamic> nutritionData = {
        'calories_per_100g': nutritionOutput.calories,
        'protein_g_per_100g': nutritionOutput.protein,
        'fats_g_per_100g': nutritionOutput.fat,
        'carbs_g_per_100g': nutritionOutput.carbs,
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultsScreen(
            imageFile: _capturedImage!,
            foodClass: classificationOutput.dishName,
            confidence: classificationOutput.confidence,
            servingSize: classificationOutput.servingSize,
            nutritionData: nutritionData,
          ),
        ),
      );
    } catch (e) {
      print('Error in _processAndProceed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Camera'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleFlash,
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (_capturedImage == null) {
              return Center(
                child: Stack(
                  children: [
                    Center(
                      child: SizedBox(
                        width: screenWidth,
                        height: screenWidth,
                        child: Stack(
                          children: [
                            CameraPreview(_cameraController),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: CameraOverlayPainter(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 50,
                      left: 20,
                      right: 20,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // زر المعرض
                          GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                color: Colors.black26,
                              ),
                              child: _lastImageFile == null
                                  ? const Icon(Icons.photo_library, color: Colors.white)
                                  : ClipOval(
                                child: Image.file(
                                  _lastImageFile!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          // زر الكاميرا
                          FloatingActionButton(
                            onPressed: _captureImage,
                            backgroundColor: Colors.white,
                            child: const Icon(Icons.camera_alt, color: Colors.black),
                          ),
                          const SizedBox(width: 50),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            } else {
              // معاينة الصورة بعد الالتقاط
              return Column(
                children: [
                  Expanded(child: Image.file(_capturedImage!)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: _discardImage,
                        icon: const Icon(Icons.clear),
                        label: const Text('إلغاء'),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        onPressed: _processAndProceed,
                        icon: const Icon(Icons.check),
                        label: const Text('موافق'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              );
            }
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}

/// CustomPainter لرسم تراكب إطار الكاميرا مع أحرف L في كل زاوية
class CameraOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final double cornerLength = 20.0;

    // الزاوية العلوية اليسرى
    canvas.drawLine(Offset(0, 0), Offset(cornerLength, 0), paint);
    canvas.drawLine(Offset(0, 0), Offset(0, cornerLength), paint);

    // الزاوية العلوية اليمنى
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - cornerLength, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, cornerLength), paint);

    // الزاوية السفلية اليسرى
    canvas.drawLine(Offset(0, size.width), Offset(0, size.width - cornerLength), paint);
    canvas.drawLine(Offset(0, size.width), Offset(cornerLength, size.width), paint);

    // الزاوية السفلية اليمنى
    canvas.drawLine(Offset(size.width, size.width), Offset(size.width - cornerLength, size.width), paint);
    canvas.drawLine(Offset(size.width, size.width), Offset(size.width, size.width - cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}