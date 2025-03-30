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
// استيراد صفحة النتائج
import 'history_data.dart';
import 'results_screen.dart';
// استيراد صفحة السجل وإدارة التخزين
import 'HistoryStorage.dart';

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
      setState(() {});
    } catch (e) {
      print('Error capturing image: $e');
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile =
      await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        _capturedImage = File(pickedFile.path);
        _lastImageFile = _capturedImage;
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

  Future<void> _processAndProceed() async {
    if (_capturedImage == null) return;
    try {
      final bytes = await _capturedImage!.readAsBytes();
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) {
        throw Exception('Failed to decode image');
      }

      final floatList = DeepLearning.loadImageAsFloatList(decodedImage, 300, 300);

      // التصنيف
      final classificationInput = ClassificationModelInput(imageData: floatList);
      final dishClassification = DishClassification();
      await dishClassification.loadModel();
      await dishClassification.loadLabels();
      final classificationOutput =
      await dishClassification.classifyDish(classificationInput);

      // التحليل الغذائي
      final nutritionInput = NutritionModelInput(imageData: floatList);
      final dishNutritionRegression = DishNutritionRegression();
      await dishNutritionRegression.loadModel();
      final nutritionOutput =
      await dishNutritionRegression.predictNutrition(nutritionInput);

      // حفظ البيانات في السجل باستخدام SharedPreferences
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

      // الانتقال إلى صفحة النتائج
      final Map<String, dynamic> nutritionData = {
        'calories_per_100g': nutritionOutput.calories,
        'protein_g_per_100g': nutritionOutput.protein,
        'fats_g_per_100g': nutritionOutput.fat,
        'carbs_g_per_100g': nutritionOutput.carbs,
        'fiber_g_per_100g': nutritionOutput.fiber ?? 0,
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
    // الحصول على عرض الشاشة لتحديد حجم الإطار المربع
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
              return Stack(
                children: [
                  // عرض معاينة الكاميرا ضمن إطار مربع يغطي عرض الشاشة
                  Center(
                    child: ClipRect(
                      child: SizedBox(
                        width: screenWidth,
                        height: screenWidth,
                        child: CameraPreview(_cameraController),
                      ),
                    ),
                  ),
                  // إطار مربع يظهر في وسط الشاشة لتأكيد أن المعاينة مربعة
                  Center(
                    child: Container(
                      width: screenWidth,
                      height: screenWidth,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
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
                        // الدائرة الصغيرة لعرض آخر صورة من المعرض
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
                                ? const Icon(
                              Icons.photo_library,
                              color: Colors.white,
                            )
                                : ClipOval(
                              child: Image.file(
                                _lastImageFile!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        // زر التقاط الصورة
                        FloatingActionButton(
                          onPressed: _captureImage,
                          backgroundColor: Colors.white,
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.black,
                          ),
                        ),
                        // مساحة افتراضية
                        const SizedBox(width: 50),
                      ],
                    ),
                  ),
                ],
              );
            } else {
              // عرض المعاينة مع أزرار الإلغاء والموافقة
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
