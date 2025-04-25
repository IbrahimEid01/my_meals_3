import 'dart:developer';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image/image.dart' as img; // Keep image library import if needed elsewhere, though DeepLearning handles it now
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
import 'package:tflite_flutter/tflite_flutter.dart';
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
  bool _isFlashOn = false; // Keep track of flash state for UI icon
  // File? _lastImageFile; // _capturedImage serves this purpose
  final DishClassification _dishClassification = DishClassification();
  final DishNutritionRegression _dishNutritionRegression = DishNutritionRegression();
  FToast? fToast;

  @override
  void initState() {
    super.initState();
    _initializeControllerFuture = _initCamera();
    fToast = FToast();
    // Ensure FToast is initialized after the first frame
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
        orElse: () => cameras.first, // Fallback to the first available camera
      );

      _cameraController = CameraController(
        firstCamera,
        ResolutionPreset.high, // Use high resolution
        enableAudio: false, // Audio not needed
        // *MODIFICATION: Use bgra8888 for uncompressed data*
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

try {
  final interpreter = await Interpreter.fromAsset('models2/classification_model.tflite');
  final inputs = interpreter.getInputTensors();
  final outputs = interpreter.getOutputTensors();
  log('✅ Loaded TFLite model successfully!');
  log('Input tensors: $inputs');
  log('Output tensors: $outputs');
} catch (e) {
  log('❌ Failed to load TFLite model: $e');
}
      await _cameraController!.initialize();
      // Set initial flash mode based on _isFlashOn (default is off)
      await _cameraController!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
      log("Camera controller initialized successfully with format: ${_cameraController!.imageFormatGroup}");
      // Refresh the UI after initialization completes
      if (mounted) setState(() {});
    } catch (e, stacktrace) {
      log('CRITICAL Error initializing camera: $e');
      log('Stacktrace: $stacktrace');
      // Optionally show a toast or update UI to inform the user
      _showToast('فشل خطير في تهيئة الكاميرا', Colors.redAccent);
      // Re-throw to allow FutureBuilder to catch it
      throw Exception('Failed to initialize camera: $e');
    }
  }

  // *MODIFIED: _processAndProceed with detailed logging and partial results*
  Future<void> _processAndProceed() async {
    log('[_processAndProceed] Started.'); // Log start

    if (_capturedImage == null) {
      log("[_processAndProceed] Processing skipped: No image captured.");
      _showToast("الرجاء التقاط صورة أولاً", Colors.orange);
      return;
    }
    if (_isProcessing) {
      log("[_processAndProceed] Processing skipped: Already processing.");
      return;
    }
    // Ensure fToast is initialized (it might be null if context wasn't ready before)
    if (fToast == null && mounted) fToast = FToast()..init(context);

    setState(() => _isProcessing = true);
    _showToast("جاري معالجة الصورة...", Colors.blueGrey);

    ClassificationModelOutput? classificationResult;
    NutritionModelOutput? nutritionResult;
    String? processingError; // To store the first error message encountered

    try {
      log("[_processAndProceed] Reading image bytes...");
      final Uint8List bytes = await _capturedImage!.readAsBytes();
      log("[_processAndProceed] Image bytes read successfully (${bytes.lengthInBytes} bytes).");

      // --- Classification ---
      log("[_processAndProceed] --- Starting Classification ---");
      try {
        log("[_processAndProceed] Preprocessing for Classification (${AppConstants.classificationInputSize}x${AppConstants.classificationInputSize})...");
        Float32List inputDataClass = await DeepLearning.loadImageAndPreprocess(
          bytes,
          AppConstants.classificationInputSize,
          applySegmentation: false, // No segmentation for classification
        );
        log("[_processAndProceed] Classification preprocessing successful.");

        final classificationInput = ClassificationModelInput(
          imageData: inputDataClass.buffer.asFloat32List().cast<double>().toList(),
        );
        log("[_processAndProceed] Running classification model...");
        classificationResult = await _dishClassification.classifyDish(classificationInput);
        log('[Classification Result]: ${classificationResult.dishName} (Conf: ${classificationResult.confidence})');

        // Check for specific error messages from the model wrapper if implemented
        if (classificationResult.dishName.toLowerCase().contains("error")) {
          throw Exception("Model wrapper returned error: ${classificationResult.dishName}");
        }
        log("[_processAndProceed] Classification successful.");

      } catch (e, stacktrace) {
        log('[ERROR] Classification failed: $e');
        log('Stacktrace: $stacktrace');
        processingError ??= "فشل التعرف على الطبق."; // Store only the first error
        classificationResult = null; // Ensure it's null on error
      }

      // --- Nutrition ---
      log("[_processAndProceed] --- Starting Nutrition Analysis ---");
      try {
        log("[_processAndProceed] Preprocessing for Nutrition (${AppConstants.nutritionInputSize}x${AppConstants.nutritionInputSize}) with segmentation...");
        Float32List inputDataNutr = await DeepLearning.loadImageAndPreprocess(
          bytes,
          AppConstants.nutritionInputSize,
          applySegmentation: true, // Apply segmentation for nutrition
        );
        log("[_processAndProceed] Nutrition preprocessing successful.");

        final nutritionInput = NutritionModelInput(
          imageData: inputDataNutr.buffer.asFloat32List().cast<double>().toList(),
        );
        log("[_processAndProceed] Running nutrition model...");
        nutritionResult = await _dishNutritionRegression.predictNutrition(nutritionInput);
        log('[Nutrition Result]: Cal=${nutritionResult.calories.toStringAsFixed(1)}, Mass=${nutritionResult.mass.toStringAsFixed(1)}g, Fat=${nutritionResult.fat.toStringAsFixed(1)}g, Carbs=${nutritionResult.carbs.toStringAsFixed(1)}g, Protein=${nutritionResult.protein.toStringAsFixed(1)}g');

        // Check if all nutrition values are zero/invalid (indicating failure)
        if (nutritionResult.calories <= 0 &&
            nutritionResult.mass <= 0 &&
            nutritionResult.fat <= 0 &&
            nutritionResult.carbs <= 0 &&
            nutritionResult.protein <= 0) {
          log("[Warning] Nutrition analysis resulted in zero or invalid values.");
          throw Exception("فشل تحليل التغذية (نتائج غير صالحة).");
        }
        log("[_processAndProceed] Nutrition analysis successful.");

      } catch (e, stacktrace) {
        log('[ERROR] Nutrition analysis failed: $e');
        log('Stacktrace: $stacktrace');
        processingError ??= "فشل تحليل التغذية."; // Store only the first error
        nutritionResult = null; // Ensure it's null on error
      }

      // --- Save History and Navigate ---
      log("[_processAndProceed] --- Finalizing and Navigating ---");
      // Proceed to ResultsScreen if at least one model succeeded
      if (classificationResult != null || nutritionResult != null) {
        log("[_processAndProceed] At least one model succeeded. Saving to history (if classification available)...");

        // Example Policy: Only save history if classification was successful
        if (classificationResult != null) {
          try {
            final newEntry = HistoryEntry(
              imagePath: _capturedImage!.path,
              dishName: classificationResult.dishName, // Use actual result
              confidence: classificationResult.confidence,
              calories: nutritionResult?.calories ?? 0.0, // Use result or 0.0 if nutrition failed
              mass: nutritionResult?.mass ?? 0.0,
              fat: nutritionResult?.fat ?? 0.0,
              carbs: nutritionResult?.carbs ?? 0.0,
              protein: nutritionResult?.protein ?? 0.0,
              servingSize: '${nutritionResult?.mass?.toStringAsFixed(1) ?? 'N/A'} g', // Handle null mass
              dateTime: DateTime.now(),
            );
            List<HistoryEntry> historyEntries = await HistoryStorage.loadHistory();
            historyEntries.add(newEntry);
            await HistoryStorage.saveHistory(historyEntries);
            log("[_processAndProceed] Meal data saved to history.");
          } catch (e, stacktrace) {
            log("[ERROR] Failed to save history: $e");
            log("Stacktrace: $stacktrace");
            // Decide if this error should prevent navigation or just be logged
            _showToast("خطأ في حفظ السجل", Colors.orange);
          }
        } else {
          log("[_processAndProceed] Skipping history save as classification failed.");
        }

        // Show appropriate completion message
        _showToast(
            processingError == null ? "اكتمل التحليل!" : "اكتمل التحليل (مع بعض الأخطاء)",
            processingError == null ? Colors.green : Colors.orangeAccent);

        log("[_processAndProceed] Navigating to ResultsScreen...");
        // Use pushReplacement to prevent going back to the camera screen easily
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ResultsScreen(
              imageFile: _capturedImage!,
              // Pass actual results or default values/placeholders
              foodClass: classificationResult?.dishName ?? "لم يتم التعرف عليه",
              confidence: classificationResult?.confidence ?? 0.0,
              calories: nutritionResult?.calories ?? 0.0,
              mass: nutritionResult?.mass ?? 0.0,
              fat: nutritionResult?.fat ?? 0.0,
              carbs: nutritionResult?.carbs ?? 0.0,
              protein: nutritionResult?.protein ?? 0.0,
              // You might want to pass the error status too
              // classificationError: classificationResult == null,
              // nutritionError: nutritionResult == null,
            ),
          ),
        ).then((_) {
          // This block executes after ResultsScreen is popped (if it allows popping)
          // or if pushReplacement itself completes. Reset state here.
          log("[_processAndProceed] Navigation Future completed.");
          if (mounted) {
            setState(() {
              _isProcessing = false;
              // Optionally clear the image? Or leave it for user?
              // _capturedImage = null;
            });
            log("[_processAndProceed] State reset: _isProcessing = false");
          }
        });
        log("[_processAndProceed] Navigation initiated.");
        // IMPORTANT: Do not reset _isProcessing here immediately,
        // let the .then() block handle it after navigation completes/pops.

      } else {
        // Both models failed
        log("[_processAndProceed] Both models failed. Not navigating.");
        _showToast(processingError ?? 'فشل التحليل بالكامل', Colors.redAccent);
        if (mounted) setState(() => _isProcessing = false); // Reset state here as navigation won't happen
      }

    } catch (e, stacktrace) { // Catch critical errors like reading file bytes
      log('[CRITICAL ERROR] in _processAndProceed outer try-catch: $e');
      log('Stacktrace: $stacktrace');
      _showToast('خطأ فادح أثناء المعالجة: حاول مرة أخرى', Colors.redAccent);
      if (mounted) setState(() => _isProcessing = false); // Reset state on critical failure
    } finally {
      // This block executes regardless of errors within the try block,
      // but after navigation is initiated if it happens.
      // Be careful about resetting state here if navigation is involved.
      log("[_processAndProceed] Outer finally block reached.");
      // Resetting state is primarily handled by the .then() after pushReplacement
      // or when navigation doesn't occur (both models fail / critical error).
    }
  }


  void _showToast(String message, Color backgroundColor) {
    // Ensure fToast is available, initialize if needed and possible
    if (fToast == null && mounted) {
      fToast = FToast()..init(context);
      log("FToast initialized in _showToast");
    }
    if (fToast == null) {
      log("Warning: FToast is null in _showToast, cannot display message.");
      return; // Cannot show toast if FToast is still null
    }

    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25.0),
        color: backgroundColor.withOpacity(0.85),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center, // Center align text
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
    );
    // Use removeCustomToast first to prevent queuing multiple toasts if tapped quickly
    fToast?.removeCustomToast();
    fToast?.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: const Duration(seconds: 3), // Slightly longer duration
    );
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      log("Flash toggle failed: Camera not initialized.");
      _showToast('الكاميرا غير جاهزة لتغيير الفلاش', Colors.orange);
      return;
    }
    try {
      // Ensure initialization is complete before accessing value
      await _initializeControllerFuture;
      final currentMode = _cameraController!.value.flashMode;
      log("Current flash mode: $currentMode");
      final nextMode = currentMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
      await _cameraController!.setFlashMode(nextMode);

      // Update internal state after successful setting
      _isFlashOn = nextMode == FlashMode.torch;
      log("Flash mode set to: $nextMode. _isFlashOn = $_isFlashOn");
      if (mounted) setState(() {}); // Update UI to reflect flash icon change
    } catch (e) {
      log('Error toggling flash: $e');
      _showToast('فشل تغيير الفلاش', Colors.redAccent);
    }
  }

  Future<void> _captureImage() async {
    log("[_captureImage] Attempting to capture image...");
    if (_isProcessing || _cameraController == null || !_cameraController!.value.isInitialized) {
      log("[_captureImage] Capture prevented: Processing=$_isProcessing, CameraReady=${_cameraController?.value.isInitialized}");
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        _showToast('الكاميرا غير جاهزة أو التهيئة لم تكتمل', Colors.orange);
      } else if (_isProcessing) {
        _showToast('المعالجة جارية، يرجى الانتظار', Colors.orange);
      }
      return;
    }

    try {
      // Ensure controller is ready
      await _initializeControllerFuture;
      log("[_captureImage] Camera initialized, taking picture...");

      // Optionally lock focus before taking picture for better results
      // await _cameraController!.setFocusMode(FocusMode.locked);
      // await Future.delayed(Duration(milliseconds: 200)); // Short delay for focus lock

      final XFile image = await _cameraController!.takePicture();

      // Optionally unlock focus after taking picture
      // await _cameraController!.setFocusMode(FocusMode.auto);

      _capturedImage = File(image.path);
      // _lastImageFile = _capturedImage; // Redundant, use _capturedImage
      log("[_captureImage] Picture taken successfully: ${image.path}");
      if (mounted) {
        setState(() {}); // Update UI to show the captured image
      }
      _showToast("تم التقاط الصورة بنجاح!", Colors.blueGrey);
    } catch (e, stacktrace) {
      log('[ERROR] Error capturing image: $e');
      log('Stacktrace: $stacktrace');
      _showToast('فشل التقاط الصورة، حاول مرة أخرى', Colors.redAccent);
      // Optionally unlock focus in case of error during capture
      // try { await cameraController?.setFocusMode(FocusMode.auto); } catch () {}
    }
  }

  Future<void> _pickImage() async {
    log("[_pickImage] Attempting to pick image...");
    if (_isProcessing) {
      log("[_pickImage] Pick prevented: Processing=$_isProcessing");
      _showToast('المعالجة جارية، يرجى الانتظار', Colors.orange);
      return;
    }
    try {
      log("[_pickImage] Launching image picker...");
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      if (pickedFile != null) {
        _capturedImage = File(pickedFile.path);
        // _lastImageFile = _capturedImage; // Redundant
        log("[_pickImage] Image picked successfully: ${pickedFile.path}");
        if (mounted) {
          setState(() {}); // Update UI to show picked image
        }
        _showToast("تم اختيار الصورة بنجاح!", Colors.blueGrey);
      } else {
        log("[_pickImage] Image picking cancelled by user.");
      }
    } catch (e, stacktrace) {
      log('[ERROR] Error picking image: $e');
      log('Stacktrace: $stacktrace');
      _showToast('فشل اختيار الصورة', Colors.redAccent);
    }
  }

  void _discardImage() {
    log("[_discardImage] Discarding captured/picked image.");
    if (mounted) {
      setState(() {
        _capturedImage = null;
        _isProcessing = false; // Ensure processing stops if discard happens mid-way (though unlikely)
      });
      log("[_discardImage] State updated: _capturedImage = null, _isProcessing = false");
    }
  }

  @override
  void dispose() {
    log("[dispose] Disposing CustomCameraScreen.");
    // Dispose camera controller safely
    // Use Future.microtask to ensure it runs after the current build cycle if needed
    Future.microtask(() async {
      try {
        // Await initialization future ONLY if it hasn't completed with an error
        // Now it's safer to dispose
        if (_initializeControllerFuture != null) {
          try {
            await _initializeControllerFuture;
          } catch (e) {
            log("[dispose] Error during camera initialization: $e");
          }
        }
        await _cameraController?.dispose();
        log("[dispose] Camera controller disposed.");
      } catch (e) {
        log("[dispose] Error disposing camera controller: $e");
        // Don't rethrow here
      } finally {
        _cameraController = null; // Ensure it's null after attempt
        _initializeControllerFuture = null;
      }
    });

    // Close TFLite models
    try {
      _dishClassification.close();
      log("[dispose] DishClassification closed.");
    } catch (e) {
      log("[dispose] Error closing DishClassification: $e");
    }
    try {
      _dishNutritionRegression.close();
      log("[dispose] DishNutritionRegression closed.");
    } catch (e) {
      log("[dispose] Error closing DishNutritionRegression: $e");
    }

    // Cancel any active toasts
    fToast?.removeCustomToast();
    fToast?.removeCustomToast(); // Remove any active toast
    super.dispose();
    log("[dispose] CustomCameraScreen dispose finished.");
  }

  @override
  Widget build(BuildContext context) {
    log("[build] Building CustomCameraScreen UI...");
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    // Viewfinder size is the screen width (1:1 aspect ratio)
    final double squareSize = screenWidth;
    // Calculate the height of the top/bottom overlay bars
    final double overlayHeight = (screenHeight - squareSize) / 2;

    return Scaffold(
      extendBodyBehindAppBar: true, // AppBar floats over body
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Make AppBar transparent
        elevation: 0, // No shadow
        leading: IconButton(
          // Add background circle for better visibility
          icon: CircleAvatar(
              backgroundColor: Colors.black.withOpacity(0.5),
              child: const Icon(Icons.close, color: Colors.white)
          ),
          onPressed: _isProcessing ? null : () {
            log("[AppBar] Close button pressed.");
            Navigator.pop(context);
          } ,
        ),
        actions: [
          // Show flash button only if camera is ready and has flash capability
          // Use a FutureBuilder to ensure controller is initialized
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              // Check connection state and if controller is ready and has flash
              if (snapshot.connectionState == ConnectionState.done &&
                  snapshot.error == null && // Ensure no error during init
                  _cameraController != null &&
                  _cameraController!.value.isInitialized &&
                  _cameraController!.value.flashMode != null) { // Check if flash is supported
                return IconButton(
                  // Add background circle for better visibility
                  icon: CircleAvatar(
                      backgroundColor: Colors.black.withOpacity(0.5),
                      child: Icon(
                          _isFlashOn ? Icons.flash_on : Icons.flash_off, // Reflect actual state
                          color: Colors.white
                      )
                  ),
                  onPressed: _isProcessing ? null : _toggleFlash,
                );
              }
              // Return an empty container if not ready or no flash
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      backgroundColor: Colors.black, // Background for areas outside camera preview
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          log("[FutureBuilder] Camera init state: ${snapshot.connectionState}");
          // Show loading indicator while waiting for camera
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          // Show error message if initialization failed
          if (snapshot.hasError || _cameraController == null || !_cameraController!.value.isInitialized) {
            log("[FutureBuilder] Error state: ${snapshot.error ?? 'Camera controller null or not initialized'}");
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  'فشل تهيئة الكاميرا.\nيرجى التحقق من الأذونات وإعادة المحاولة.\n${snapshot.error?.toString() ?? ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            );
          }

          // --- Camera Preview or Captured Image ---
          log("[FutureBuilder] Camera ready, building preview/image stack.");
          return Stack(
            alignment: Alignment.center, // Center viewfinder and overlays
            children: [
              // --- Camera Preview ---
              // Use SizedBox + FittedBox + AspectRatio to show camera feed correctly
              if (_capturedImage == null)
                SizedBox(
                  width: screenWidth,
                  height: screenHeight,
                  child: FittedBox(
                    fit: BoxFit.cover, // Cover the whole screen area
                    child: SizedBox(
                      // Use camera's aspect ratio to size the preview correctly
                      width: screenWidth, // Match screen width initially
                      height: screenWidth / _cameraController!.value.aspectRatio,
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                ),

              // --- Captured Image Display ---
              if (_capturedImage != null)
                Container(
                  color: Colors.black, // Black background for image view
                  width: double.infinity,
                  height: double.infinity,
                  child: Center( // Center the image within the view
                    child: Padding(
                      padding: const EdgeInsets.all(16.0), // Add some padding
                      child: Image.file(
                        _capturedImage!,
                        fit: BoxFit.contain, // Show the whole image without cropping
                      ),
                    ),
                  ),
                ),

              // --- Overlays (Only when camera preview is active) ---
              if (_capturedImage == null) ...[
                // Top Overlay
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  // Ensure height is not negative if screen is short
                  height: overlayHeight > 0 ? overlayHeight : 0,
                  child: Container(
                    // Use a gradient for a smoother look (optional)
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withOpacity(0.7), Colors.black.withOpacity(0.0)],
                        )
                    ),
                    // child: Container(color: Colors.black.withOpacity(0.5)), // Simpler version
                  ),
                ),
                // Bottom Overlay
                Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: overlayHeight > 0 ? overlayHeight : 0,
                    child: Container(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black.withOpacity(0.7), Colors.black.withOpacity(0.0)],
                          )
                      ),
                      // child: Container(color: Colors.black.withOpacity(0.5)), // Simpler version
                    )
                ),
                // Square Viewfinder Border (Centered)
                Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: squareSize,
                    height: squareSize,
                    child: CustomPaint(painter: CameraOverlayPainter()),
                  ),
                ),
              ], // End of overlays section

              // --- Bottom Buttons ---
              Positioned(
                bottom: 30, // Adjust vertical position as needed
                left: 0,
                right: 0,
                child: _buildBottomButtons(), // Use helper method for buttons
              ),
            ],
          );
        },
      ),
    );
  }

  // Helper method to build bottom buttons row
  Widget _buildBottomButtons() {
    // --- Capture/Pick Buttons ---
    if (_capturedImage == null) {
      return Column(
        mainAxisSize: MainAxisSize.min, // Take minimum space needed
        children: [
          // Optional: Show processing indicator above buttons if processing
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.only(bottom: 15.0),
              child: CircularProgressIndicator(color: Colors.white),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Gallery Button
              IconButton(
                icon: const Icon(Icons.photo_library, color: Colors.white, size: 30),
                // Add background circle for better visibility
                style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.4),
                    padding: const EdgeInsets.all(15) // Adjust padding
                ),
                tooltip: "اختيار صورة",
                onPressed: _isProcessing ? null : _pickImage,
              ),
              // Capture Button
              GestureDetector(
                onTap: _isProcessing ? null : _captureImage,
                child: Container(
                  width: 75, // Slightly larger capture button
                  height: 75,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade400, width: 4) // Outer ring
                  ),
                  child: Center(
                    child: Icon( // Inner icon (optional)
                      Icons.camera_alt,
                      size: 35,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              // Placeholder for symmetry or another button (like flip camera)
              const SizedBox(width: 30 + 30), // Match IconButton size + padding approx
            ],
          ),
        ],
      );
    }
    // --- Discard/Analyze Buttons ---
    else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Optional: Show processing indicator when analyzing
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: CircularProgressIndicator(color: Colors.white),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 10.0, // Reduced vertical padding
              horizontal: 20,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Discard Button
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.red.withOpacity(0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),

                  ),
                  onPressed: _isProcessing ? null : _discardImage,
                  icon: const Icon(Icons.close),
                  label: const Text(
                    'إلغاء',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                // Analyze Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.withOpacity(0.9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 5, // Add some elevation
                  ),
                  onPressed: _isProcessing ? null : _processAndProceed,
                  icon: const Icon(Icons.check_circle_outline), // More descriptive icon
                  label: const Text(
                    'تحليل',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
  }
}

// --- Camera Overlay Painter (No changes needed based on request) ---
class CameraOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double boxSize = size.width; // Assumes square size is passed
    final double strokeWidth = 3;
    final Color lineColor = Colors.white.withOpacity(0.8); // Slightly more opaque
    final double cornerLength = 30.0;

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round; // Nicer corners

    // Draw corners
    // Top-left
    canvas.drawLine(const Offset(0, 0), Offset(cornerLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(0, cornerLength), paint);
    // Top-right
    canvas.drawLine(Offset(boxSize, 0), Offset(boxSize - cornerLength, 0), paint);
    canvas.drawLine(Offset(boxSize, 0), Offset(boxSize, cornerLength), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, boxSize), Offset(cornerLength, boxSize), paint);
    canvas.drawLine(Offset(0, boxSize), Offset(0, boxSize - cornerLength), paint);
    // Bottom-right
    canvas.drawLine(Offset(boxSize, boxSize), Offset(boxSize - cornerLength, boxSize), paint);
    canvas.drawLine(Offset(boxSize, boxSize), Offset(boxSize, boxSize - cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}