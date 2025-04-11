// lib/screens/CustomCameraScreen.dart
import 'dart:async';
import 'dart:developer'; // لاستخدام log
import 'dart:io';
import 'dart:math' hide log;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img; // لاستخدام مكتبة image
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/ClassificationModelInput.dart';
import '../models/ClassificationModelOutput.dart';
import '../models/NutritionModelInput.dart';
import '../models/NutritionModelOutput.dart';
import '../models/DishClassification.dart';
import '../models/DishNutritionRegression.dart';
import '../models/HistoryEntry.dart';
import '../utils/DeepLearning.dart';
import '../utils/constants.dart';
import 'HistoryStorage.dart';
import 'results_screen.dart';

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
  bool _isProcessing = false;
  bool _isFlashOn = false;
  File? _lastImageFile;

  // إنشاء كائنات لتحليل الأطباق
  final DishClassification _dishClassification = DishClassification();
  final DishNutritionRegression _dishNutritionRegression = DishNutritionRegression();

  @override
  void initState() {
    super.initState();
    _initializeControllerFuture = _initCamera();
    log("CustomCameraScreen initialized.");
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      // استخدام الكاميرا الخلفية
      final firstCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        firstCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _cameraController.initialize();
      if (mounted) setState(() {});
      log("Camera initialized successfully.");
    } catch (e) {
      log("Error initializing camera: $e");
      if (mounted) _showErrorSnackBar('Failed to initialize camera: $e');
    }
  }

  Future<void> _toggleFlash() async {
    if (!_cameraController.value.isInitialized) {
      log("Flash toggle failed: Camera not initialized.");
      return;
    }
    try {
      await _initializeControllerFuture;
      final currentMode = _cameraController.value.flashMode;
      final nextMode = currentMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
      await _cameraController.setFlashMode(nextMode);
      _isFlashOn = nextMode == FlashMode.torch;
      if (mounted) setState(() {});
      log("Flash mode set to: $nextMode");
    } catch (e) {
      log("Error toggling flash: $e");
      _showErrorSnackBar('Failed to toggle flash: $e');
    }
  }

  Future<void> _captureImage() async {
    if (_isProcessing) return;
    if (!_cameraController.value.isInitialized) {
      log("Capture failed: Camera not initialized.");
      return;
    }
    try {
      await _initializeControllerFuture;
      log("Taking picture...");
      final image = await _cameraController.takePicture();
      _capturedImage = File(image.path);
      _lastImageFile = _capturedImage;
      log("Picture taken successfully: ${_capturedImage!.path}");
      if (mounted) setState(() {});
      _showInfoSnackBar("Picture captured!");
    } catch (e) {
      log("Error capturing image: $e");
      _showErrorSnackBar('Failed to capture image: $e');
    }
  }

  Future<void> _pickImage() async {
    if (_isProcessing) return;
    try {
      log("Picking image from gallery...");
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        _capturedImage = File(pickedFile.path);
        _lastImageFile = _capturedImage;
        log("Image picked successfully: ${pickedFile.path}");
        if (mounted) setState(() {});
        _showInfoSnackBar("Image selected!");
      } else {
        log("Image picking cancelled by user.");
      }
    } catch (e) {
      log("Error picking image: $e");
      _showErrorSnackBar('Failed to pick image: $e');
    }
  }

  void _discardImage() {
    log("Discarding captured image.");
    if (mounted) {
      setState(() {
        _capturedImage = null;
        _isProcessing = false;
      });
    }
  }

  /// دالة اقتصاص الصورة لتصبح مربعة (1:1)
  img.Image _cropToSquare(img.Image original) {
    int width = original.width;
    int height = original.height;
    int size = width < height ? width : height;
    int xOffset = ((width - size) ~/ 2);
    int yOffset = ((height - size) ~/ 2);
    return img.copyCrop(original, x: xOffset, y: yOffset, width: size, height: size);
  }

  Future<void> _processAndProceed() async {
    if (_capturedImage == null) {
      log("Processing skipped: No image captured.");
      return;
    }
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    _showInfoSnackBar("Processing image...");

    try {
      log("Starting image processing pipeline...");
      final bytes = await _capturedImage!.readAsBytes();
      img.Image? decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) {
        throw Exception('Failed to decode image');
      }
      log("Image decoded successfully (${decodedImage.width}x${decodedImage.height}).");

      // اقتصاص الصورة لتصبح مربعة 1:1
      decodedImage = _cropToSquare(decodedImage);
      log("Image cropped to square: ${decodedImage.width}x${decodedImage.height}");

      // تجهيز بيانات نموذج التصنيف
      log("Preprocessing for Classification (${AppConstants.classificationInputSize}x${AppConstants.classificationInputSize})...");
      // نفترض أن DeepLearning.loadImageAndPreprocess تقوم بإرجاع Float32List
      Float32List inputDataClass = await DeepLearning.loadImageAndPreprocess(
        bytes,
        AppConstants.classificationInputSize,
        applySegmentation: true,
      );
      final classificationInput = ClassificationModelInput(
          imageData: inputDataClass.buffer.asFloat32List().cast<double>().toList()
      );

      // تشغيل نموذج التصنيف
      ClassificationModelOutput classificationOutput = await _dishClassification.classifyDish(classificationInput);
      log("Classification Result: ${classificationOutput.dishName} (Conf: ${classificationOutput.confidence})");

      if (classificationOutput.dishName.contains("Error")) {
        throw Exception("Classification failed: ${classificationOutput.dishName}");
      }

      // تجهيز بيانات نموذج التغذية
      log("Preprocessing for Nutrition (${AppConstants.nutritionInputSize}x${AppConstants.nutritionInputSize})...");
      Float32List inputDataNutr = await DeepLearning.loadImageAndPreprocess(
        bytes,
        AppConstants.nutritionInputSize,
        applySegmentation: true,
      );
      final nutritionInput = NutritionModelInput(
          imageData: inputDataNutr.buffer.asFloat32List().cast<double>().toList()
      );

      // تشغيل نموذج التغذية
      NutritionModelOutput nutritionOutput = await _dishNutritionRegression.predictNutrition(nutritionInput);
      log("Nutrition Result: Cal=${nutritionOutput.calories.toStringAsFixed(1)}, Mass=${nutritionOutput.mass.toStringAsFixed(1)}g, Fat=${nutritionOutput.fat.toStringAsFixed(1)}, Carbs=${nutritionOutput.carbs.toStringAsFixed(1)}, Protein=${nutritionOutput.protein.toStringAsFixed(1)}");

      if (nutritionOutput.calories <= 0 && nutritionOutput.mass <= 0) {
        throw Exception("Nutrition analysis failed to produce valid results.");
      }

      // حفظ بيانات الوجبة في السجل
      final newEntry = HistoryEntry(
        imagePath: _capturedImage!.path,
        dishName: classificationOutput.dishName,
        confidence: classificationOutput.confidence,
        calories: nutritionOutput.calories,
        mass: nutritionOutput.mass,
        fat: nutritionOutput.fat,
        carbs: nutritionOutput.carbs,
        protein: nutritionOutput.protein,
        servingSize: '${nutritionOutput.mass.toStringAsFixed(1)} g',
        dateTime: DateTime.now(),
      );
      List<HistoryEntry> historyEntries = await HistoryStorage.loadHistory();
      historyEntries.add(newEntry);
      await HistoryStorage.saveHistory(historyEntries);
      log("Meal data saved to history.");

      _showInfoSnackBar("Analysis complete!");

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ResultsScreen(
            imageFile: _capturedImage!,
            foodClass: classificationOutput.dishName,
            confidence: classificationOutput.confidence,
            calories: nutritionOutput.calories,
            mass: nutritionOutput.mass,
            fat: nutritionOutput.fat,
            carbs: nutritionOutput.carbs,
            protein: nutritionOutput.protein,
          ),
        ),
      );
      log("Navigated to ResultsScreen.");
    } catch (e) {
      log("Error in _processAndProceed: $e");
      _showErrorSnackBar('Processing failed: ${e.toString().split(':').last.trim()}');
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    } finally {
      log("Processing pipeline finished.");
    }
  }

  // دوال مساعدة لعرض SnackBar للمعلومات
  void _showInfoSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.blueGrey,
        ),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  void dispose() {
    log("Disposing CustomCameraScreen.");
    _initializeControllerFuture.then((value) {
      _cameraController.dispose();
      log("Camera controller disposed.");
    }).catchError((e) {
      log("Error disposing camera controller (possibly never initialized): $e");
    });
    _dishClassification.close();
    _dishNutritionRegression.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final previewSize = screenWidth * 0.9;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
        ),
        title: const Text('Take a Picture'),
        centerTitle: true,
        actions: [
          FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    _cameraController.value.isInitialized &&
                    _cameraController.value.flashMode != FlashMode.off &&
                    _cameraController.value.flashMode != FlashMode.auto) {
                  return IconButton(
                    icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
                    onPressed: _isProcessing ? null : _toggleFlash,
                  );
                }
                return const SizedBox.shrink();
              }),
        ],
        backgroundColor: AppConstants.primaryColor,
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (_capturedImage == null) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: previewSize,
                    height: previewSize,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.center,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: screenWidth,
                            height: screenWidth / _cameraController.value.aspectRatio,
                            child: CameraPreview(_cameraController),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // رسم التراكب مع إطار الكاميرا وأحرف L في كل زاوية
                  Positioned.fill(
                    child: CustomPaint(
                      painter: CameraOverlayPainter(),
                    ),
                  ),
                  Positioned(
                    bottom: 30,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        if (_isProcessing)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 15.0),
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.photo_library, color: Colors.white, size: 30),
                              onPressed: _isProcessing ? null : _pickImage,
                            ),
                            FloatingActionButton(
                              onPressed: _isProcessing ? null : _captureImage,
                              backgroundColor: Colors.white,
                              child: const Icon(Icons.camera_alt, color: Colors.black, size: 35),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            } else {
              return Column(
                children: [
                  Expanded(
                    child: Image.file(
                      _capturedImage!,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (_isProcessing)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: CircularProgressIndicator(),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
                          ),
                          onPressed: _isProcessing ? null : _discardImage,
                          icon: const Icon(Icons.close, color: Colors.white),
                          label: const Text('Discard', style: TextStyle(color: Colors.white, fontSize: 16)),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
                          ),
                          onPressed: _isProcessing ? null : _processAndProceed,
                          icon: const Icon(Icons.check, color: Colors.white),
                          label: const Text('Analyze', style: TextStyle(color: Colors.white, fontSize: 16)),
                        ),
                      ],
                    ),
                  ),
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
      ..color = Colors.white.withOpacity(0.7)
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
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - cornerLength), paint);
    canvas.drawLine(Offset(0, size.height), Offset(cornerLength, size.height), paint);

    // الزاوية السفلية اليمنى
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - cornerLength, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}