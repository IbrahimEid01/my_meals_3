import 'dart:developer';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:my_meals_3/models/DishClassification.dart';
import 'package:my_meals_3/models/DishNutritionRegression.dart';
import 'package:my_meals_3/models/ClassificationModelInput.dart';
import 'package:my_meals_3/models/ClassificationModelOutput.dart';
import 'package:my_meals_3/models/HistoryEntry.dart';
import 'package:my_meals_3/models/NutritionModelInput.dart';
import 'package:my_meals_3/models/NutritionModelOutput.dart';
import 'package:my_meals_3/utils/DeepLearning.dart';
import 'package:my_meals_3/screens/HistoryStorage.dart';
import 'package:my_meals_3/utils/constants.dart';
import 'results_screen.dart';
import 'dart:typed_data';
import 'dart:math' hide log;

class CustomCameraScreen extends StatefulWidget {
  const CustomCameraScreen({Key? key}) : super(key: key);

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen> {
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  final ImagePicker _picker = ImagePicker();
  File? _capturedImage;
  bool _isProcessing = false;
  bool _isFlashOn = false;
  File? _lastImageFile;
  final DishClassification _dishClassification = DishClassification();
  final DishNutritionRegression _dishNutritionRegression = DishNutritionRegression();
  FToast? fToast;

  @override
  void initState() {
    super.initState();
    _initializeControllerFuture = _initCamera();
    fToast = FToast();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fToast!.init(context);
    });
    log("CustomCameraScreen initialized.");
  }

  Future<void> _initCamera() async {
    try {
      log("Initializing camera...");
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        log("Error: No cameras available.");
        throw Exception("No cameras available on this device.");
      }
      final firstCamera = cameras.firstWhere(
              (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first);

      _cameraController = CameraController(
        firstCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      log("Camera controller initialized successfully.");
    } catch (e) {
      log('Error initializing camera: $e');
      throw Exception('Failed to initialize camera: $e');
    }
  }

  Future<void> _processAndProceed() async {
    if (_capturedImage == null) {
      log("Processing skipped: No image captured.");
      _showToast("الرجاء التقاط صورة أولاً", Colors.orange);
      return;
    }
    if (_isProcessing) return;
    if (fToast == null) fToast = FToast()..init(context);

    setState(() => _isProcessing = true);
    _showToast("جاري معالجة الصورة...", Colors.blueGrey);
    try {
      log("Starting image processing pipeline...");
      final bytes = await _capturedImage!.readAsBytes();

      // --- المعالجة لنموذج التصنيف (250×250 بدون تقسيم) ---
      log("Preprocessing for Classification (${AppConstants.classificationInputSize}x${AppConstants.classificationInputSize})...");
      Float32List inputDataClass = await DeepLearning.loadImageAndPreprocess(
          bytes,
          AppConstants.classificationInputSize,
          applySegmentation: false
      );
      final classificationInput = ClassificationModelInput(
          imageData: inputDataClass.buffer.asFloat32List().cast<double>().toList()
      );

      // --- المعالجة لنموذج التغذية (224×224 مع تقسيم لتفريغ الخلفية) ---
      log("Preprocessing for Nutrition (${AppConstants.nutritionInputSize}x${AppConstants.nutritionInputSize}) with segmentation...");
      Float32List inputDataNutr = await DeepLearning.loadImageAndPreprocess(
          bytes,
          AppConstants.nutritionInputSize,
          applySegmentation: true
      );
      final nutritionInput = NutritionModelInput(
          imageData: inputDataNutr.buffer.asFloat32List().cast<double>().toList()
      );

      // --- تشغيل النماذج ---
      log("Running classification model...");
      ClassificationModelOutput classificationOutput = await _dishClassification.classifyDish(classificationInput);
      log('Classification Result: ${classificationOutput.dishName} (Conf: ${classificationOutput.confidence})');
      if (classificationOutput.dishName.contains("Error"))
        throw Exception("فشل التصنيف: ${classificationOutput.dishName}");

      log("Running nutrition model...");
      NutritionModelOutput nutritionOutput = await _dishNutritionRegression.predictNutrition(nutritionInput);
      log('Nutrition Result: Cal=${nutritionOutput.calories.toStringAsFixed(1)}, Mass=${nutritionOutput.mass.toStringAsFixed(1)}g, Fat=${nutritionOutput.fat.toStringAsFixed(1)}g, Carbs=${nutritionOutput.carbs.toStringAsFixed(1)}g, Protein=${nutritionOutput.protein.toStringAsFixed(1)}g');
      if (nutritionOutput.calories <= 0 &&
          nutritionOutput.mass <= 0 &&
          nutritionOutput.fat <= 0 &&
          nutritionOutput.carbs <= 0 &&
          nutritionOutput.protein <= 0) {
        log("Warning: Nutrition analysis resulted in zero or invalid values.");
        throw Exception("فشل تحليل التغذية. حاول بصورة أوضح.");
      }

      log("Saving data to history...");
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
      _showToast("اكتمل التحليل!", Colors.green);
      log("Navigating to ResultsScreen...");
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
      ).then((_) {
        if (mounted) {
          setState(() { _isProcessing = false; });
        }
      });
      log("Navigation initiated.");
    } catch (e) {
      log('Error in _processAndProceed: $e');
      _showToast('فشل التحليل: ${e.toString()}', Colors.redAccent);
      if (mounted) {
        setState(() { _isProcessing = false; });
      }
    } finally {
      log("Processing pipeline finished.");
    }
  }

  void _showToast(String message, Color backgroundColor) {
    if (fToast == null) return;
    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25.0),
        color: backgroundColor.withOpacity(0.85),
      ),
      child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 15)),
    );
    fToast?.showToast(child: toast, gravity: ToastGravity.BOTTOM, toastDuration: const Duration(seconds: 2));
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      log("Flash toggle failed: Camera not initialized.");
      return;
    }
    try {
      await _initializeControllerFuture;
      final currentMode = _cameraController!.value.flashMode;
      final nextMode = currentMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
      await _cameraController!.setFlashMode(nextMode);
      _isFlashOn = nextMode == FlashMode.torch;
      if (mounted) setState(() {});
      log("Flash mode set to: $nextMode");
    } catch (e) {
      log('Error toggling flash: $e');
      _showToast('فشل تغيير الفلاش', Colors.redAccent);
    }
  }

  Future<void> _captureImage() async {
    if (_isProcessing || _cameraController == null || !_cameraController!.value.isInitialized) {
      log("Capture prevented: Processing=$_isProcessing, CameraReady=${_cameraController?.value.isInitialized}");
      if (_cameraController == null || !_cameraController!.value.isInitialized)
        _showToast('الكاميرا غير جاهزة', Colors.orange);
      return;
    }
    try {
      await _initializeControllerFuture;
      log("Taking picture...");
      final image = await _cameraController!.takePicture();
      _capturedImage = File(image.path);
      _lastImageFile = _capturedImage;
      log("Picture taken successfully: ${image.path}");
      if (mounted) setState(() {});
      _showToast("تم التقاط الصورة!", Colors.blueGrey);
    } catch (e) {
      log('Error capturing image: $e');
      _showToast('فشل التقاط الصورة', Colors.redAccent);
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
        _showToast("تم اختيار الصورة!", Colors.blueGrey);
      } else {
        log("Image picking cancelled by user.");
      }
    } catch (e) {
      log('Error picking image: $e');
      _showToast('فشل اختيار الصورة', Colors.redAccent);
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

  @override
  void dispose() {
    log("Disposing CustomCameraScreen.");
    Future.microtask(() async {
      if (_initializeControllerFuture != null) {
        try {
          await _initializeControllerFuture!;
          await _cameraController?.dispose();
          log("Camera controller disposed.");
        } catch (e) {
          log("Error disposing camera controller: $e");
        }
      }
    });
    _dishClassification.close();
    _dishNutritionRegression.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final double squareSize = screenWidth;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(child: const Icon(Icons.close, color: Colors.white)),
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
        ),
        actions: [
          FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    _cameraController != null &&
                    _cameraController!.value.isInitialized &&
                    _cameraController!.value.flashMode != FlashMode.off) {
                  // زر الفلاش
                  return IconButton(
                    icon: const Icon(Icons.flash_on, color: Colors.white),
                    onPressed: _isProcessing ? null : _toggleFlash,
                  );
                }
                return const SizedBox.shrink();
              }
          )
        ],
      ),
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || _cameraController == null || !_cameraController!.value.isInitialized) {
            log("FutureBuilder error state: ${snapshot.error}");
            return Center(child: Text(
                snapshot.error?.toString() ?? 'فشل تهيئة الكاميرا',
                style: const TextStyle(color: Colors.white)
            ));
          }
          return Stack(
            alignment: Alignment.center,
            children: [
              (_capturedImage == null)
                  ? SizedBox(
                width: screenWidth,
                height: screenHeight,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: screenWidth,
                    height: screenWidth / _cameraController!.value.aspectRatio,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              )
                  : Container(
                color: Colors.black,
                width: double.infinity,
                height: double.infinity,
                child: Column(
                  children: [
                    Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Image.file(
                            _capturedImage!,
                            fit: BoxFit.contain,
                          ),
                        )),
                  ],
                ),
              ),
              if (_capturedImage == null)
                SizedBox(
                    width: squareSize,
                    height: squareSize,
                    child: CustomPaint(
                      painter: CameraOverlayPainter(),
                    )),
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: (_capturedImage == null)
                    ? Column(
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
                          icon: const Icon(Icons.photo_library),
                          onPressed: _isProcessing ? null : _pickImage,
                        ),
                        GestureDetector(
                          onTap: _isProcessing ? null : _captureImage,
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.camera_alt, size: 30, color: Colors.black),
                          ),
                        ),
                        const SizedBox(width: 75),
                      ],
                    ),
                  ],
                )
                    : Column(
                  children: [
                    if (_isProcessing)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: CircularProgressIndicator(),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: Colors.white),
                            onPressed: _isProcessing ? null : _discardImage,
                            icon: const Icon(Icons.close),
                            label: const Text('إلغاء', style: TextStyle(fontSize: 16)),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                            onPressed: _isProcessing ? null : _processAndProceed,
                            icon: const Icon(Icons.check),
                            label: const Text('تحليل', style: TextStyle(fontSize: 16)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class CameraOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double boxSize = size.width;
    final double strokeWidth = 3;
    final Color lineColor = Colors.white.withOpacity(0.7);
    final double cornerLength = 30.0;

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // رسم الزوايا
    canvas.drawLine(const Offset(0, 0), Offset(cornerLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(0, cornerLength), paint);
    canvas.drawLine(Offset(boxSize, 0), Offset(boxSize - cornerLength, 0), paint);
    canvas.drawLine(Offset(boxSize, 0), Offset(boxSize, cornerLength), paint);
    canvas.drawLine(Offset(0, boxSize), Offset(cornerLength, boxSize), paint);
    canvas.drawLine(Offset(0, boxSize), Offset(0, boxSize - cornerLength), paint);
    canvas.drawLine(Offset(boxSize, boxSize), Offset(boxSize - cornerLength, boxSize), paint);
    canvas.drawLine(Offset(boxSize, boxSize), Offset(boxSize, boxSize - cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}