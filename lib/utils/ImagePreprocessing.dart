import 'dart:developer' as dev; // Keep using alias 'dev' for consistency
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'constants.dart'; // Ensure correct path
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:math' hide log; // Hide log from dart:math

class ImagePreprocessing {
  // Static variables for single DeepLabV3 instance
  static Interpreter? _interpreter;
  static bool _isLoaded = false;
  static List<int>? _inputShape;
  static TensorType? _inputType;
  static List<int>? _outputShape;
  static TensorType? _outputType;

  // Getter to check if model is loaded from outside
  static bool isModelLoaded() => _isLoaded;

  // Load DeepLabV3 Model (Static)
  static Future<void> loadDeepLabModel() async {
    if (_isLoaded && _interpreter != null && _interpreter!.address != 0) {
      dev.log("[loadDeepLabModel] DeepLabV3 model already loaded.");
      return;
    }
    dev.log("[loadDeepLabModel] Attempting to load DeepLabV3 model...");
    _isLoaded = false; // Reset status before attempt
    try {
      final interpreterOptions = InterpreterOptions();
      // Add delegates here if needed (GPU, NNAPI)
      // interpreterOptions.addDelegate(GpuDelegateV2());

      _interpreter = await Interpreter.fromAsset(
          AppConstants.segmentationModelPath, options: interpreterOptions);

      if (_interpreter == null || _interpreter!.address == 0) {
        dev.log("[ERROR] Failed loading DeepLabV3 model: Interpreter creation failed.");
        _disposeInterpreterStatic(); // Clean up potential partial resources
        return;
      }

      var inputTensors = _interpreter!.getInputTensors();
      var outputTensors = _interpreter!.getOutputTensors();

      if (inputTensors.isEmpty || outputTensors.isEmpty) {
        dev.log("[ERROR] Failed loading DeepLabV3 model: No input or output tensors found.");
        _disposeInterpreterStatic();
        return;
      }
      if (inputTensors.length > 1 || outputTensors.length > 1) {
        dev.log("[Warning] DeepLabV3 model has multiple inputs/outputs. Using the first one.");
      }

      // Store shape and type info
      _inputShape = inputTensors.first.shape;
      _inputType = inputTensors.first.type;
      _outputShape = outputTensors.first.shape;
      _outputType = outputTensors.first.type;

      // Basic validation
      if (_inputShape == null || _outputShape == null || _inputType == null || _outputType == null) {
        dev.log("[ERROR] Failed loading DeepLabV3 model: Input/Output tensor info is null.");
        _disposeInterpreterStatic();
        return;
      }

      _isLoaded = true; // Mark as loaded successfully
      dev.log("✅ [loadDeepLabModel] DeepLabV3 model loaded successfully!");
      dev.log('  Input: Shape=$_inputShape, Type=$_inputType');
      dev.log('  Output: Shape=$_outputShape, Type=$_outputType');

      // Input Shape Check (Example: [1, 513, 513, 3])
      if (_inputShape!.length != 4 || _inputShape![0] != 1 || _inputShape![1] != AppConstants.segmentationInputSize || _inputShape![2] != AppConstants.segmentationInputSize || _inputShape![3] != 3) {
        dev.log("[Warning] DeepLab input shape $_inputShape mismatch! Expected [1, ${AppConstants.segmentationInputSize}, ${AppConstants.segmentationInputSize}, 3]");
      }
      // Output Shape Check (Example: [1, 513, 513, 151] for PASCAL VOC)
      if (_outputShape!.length != 4 || _outputShape![0] != 1 || _outputShape![1] != AppConstants.segmentationInputSize || _outputShape![2] != AppConstants.segmentationInputSize || _outputShape![3] <= 0) {
        // Check if H/W match input size, C > 0
        dev.log("[Warning] DeepLab output shape $_outputShape mismatch or invalid. Expected [1, ${AppConstants.segmentationInputSize}, ${AppConstants.segmentationInputSize}, numClasses > 0]");
      }
      // Output Type Check (Usually Float32)
      if (_outputType != TensorType.float32) {
        dev.log("[Warning] DeepLab output type is $_outputType. Expected FLOAT32 for standard probability output.");
        // Code below assumes Float32 or Int32/Int64, adjust if needed
      }

    } catch (e, stacktrace) {
      dev.log("❌ [CRITICAL ERROR] loading DeepLabV3 model: $e");
      dev.log("Stacktrace: $stacktrace");
      _disposeInterpreterStatic(); // Ensure cleanup on error
    }
  }

  // Apply Segmentation (Static)
  static Future<img.Image> applySegmentation(img.Image image) async {
    if (!_isLoaded || _interpreter == null || _interpreter!.address == 0 || _inputShape == null || _outputShape == null || _outputType == null) {
      dev.log("[applySegmentation] Skipped: DeepLabV3 model not ready.");
      return image; // Return original image if model not ready
    }
    dev.log("[applySegmentation] Applying DeepLabV3 segmentation...");

    final int originalWidth = image.width;
    final int originalHeight = image.height;
    final int segHeight = _inputShape![1]; // Expected: 513
    final int segWidth = _inputShape![2];   // Expected: 513
    final int numClasses = _outputShape![3]; // Expected: 151 or other based on model

    // Validate output shape for processing logic
    if (_outputShape!.length != 4 || _outputShape![0] != 1 || numClasses <= 0) {
      dev.log("[ERROR] applySegmentation: Invalid output shape $_outputShape for processing.");
      return image;
    }

    // Resize image for DeepLabV3 input
    dev.log("[applySegmentation] Resizing image from ${originalWidth}x$originalHeight to ${segWidth}x$segHeight...");
    img.Image resizedForSegmentation = img.copyResize(image, width: segWidth, height: segHeight);
    dev.log("[applySegmentation] Image resized.");

    // Prepare input tensor (normalize)
    dev.log("[applySegmentation] Preparing input tensor...");
    Float32List inputBytes = _prepareInputTensor(resizedForSegmentation);
    // Reshape to model's expected input shape [1, H, W, C]
    var inputTensor = inputBytes.buffer.asFloat32List().reshape(_inputShape!);
    dev.log("[applySegmentation] Input tensor prepared with shape: ${_inputShape!}");


    // Prepare output buffer with reshape before running
    int outputFlatSize = 1 * segHeight * segWidth * numClasses;
    Object outputTensorBuffer;
    List<int> outputExpectedShape = [1, segHeight, segWidth, numClasses];
    dev.log("[applySegmentation] Preparing output buffer. Type: $_outputType, FlatSize: $outputFlatSize, Shape: $outputExpectedShape");

    try {
      if (_outputType == TensorType.float32) {
        outputTensorBuffer = Float32List(outputFlatSize).reshape(outputExpectedShape);
      } else if (_outputType == TensorType.int32) {
        outputTensorBuffer = Int32List(outputFlatSize).reshape(outputExpectedShape);
      } else if (_outputType == TensorType.int64) {
        // Be cautious with Int64 reshape, TFLite support might vary
        outputTensorBuffer = Int64List(outputFlatSize).reshape(outputExpectedShape);
        dev.log("[Warning] Using Int64 output buffer with reshape, ensure TFLite version compatibility.");
      } else {
        throw Exception("Unsupported output type: $_outputType");
      }
      dev.log("[applySegmentation] Output buffer created and reshaped.");
    } catch (e, stacktrace) {
      dev.log("[ERROR] Failed to create or reshape output buffer: $e");
      dev.log("Stacktrace: $stacktrace");
      return image; // Cannot proceed without output buffer
    }


    // Run Inference
    try {
      dev.log("[applySegmentation] Running segmentation inference...");
      // Log buffer details before run for debugging shape issues
      if (outputTensorBuffer is TypedData) {
        dev.log("  Output Buffer Type: ${outputTensorBuffer.runtimeType}, Length(bytes): ${(outputTensorBuffer as TypedData).buffer.lengthInBytes}");
        try {
          dev.log("  Output Buffer Shape (dynamic): ${(outputTensorBuffer as dynamic).shape}");
        } catch (_) { dev.log("  Output Buffer Shape property not accessible."); }
      }
      // Run inference
      _interpreter!.run(inputTensor, outputTensorBuffer);
      dev.log("[applySegmentation] Segmentation inference completed.");

    } catch (e, stacktrace) {
      dev.log("[ERROR] during segmentation inference: $e");
      dev.log("Stacktrace: $stacktrace");
      // Most likely error here is shape mismatch if reshape didn't work as expected by run()
      return image; // Return original image on inference failure
    }

    // Process Output and Create Mask
    try {
      dev.log("[applySegmentation] Creating segmentation mask from output...");
      // Create blank RGBA mask image
      img.Image segmentationMask = img.Image(width: segWidth, height: segHeight, numChannels: 4);

      // Process based on output type
      if (_outputType == TensorType.float32) {
        // --- Process Float32 (Probabilities) ---
        dev.log("[applySegmentation] Processing FLOAT32 output (probabilities)...");
        // Cast to expected multi-dimensional list AFTER inference
        var outputProbData = outputTensorBuffer as List<List<List<List<double>>>>;

        // Add dimension check again after cast, just in case run modified structure (unlikely but safe)
        if (outputProbData.length != 1 || outputProbData[0].length != segHeight || outputProbData[0][0].length != segWidth || outputProbData[0][0][0].length != numClasses) {
          dev.log("[ERROR] Segmentation output dimensions mismatch after inference. Aborting mask creation.");
          return image;
        }

        for (int y = 0; y < segHeight; y++) {
          for (int x = 0; x < segWidth; x++) {
            int bestClass = -1;
            double maxProb = -double.infinity;
            for (int c = 0; c < numClasses; c++) {
              double currentProb = outputProbData[0][y][x][c];
              if (currentProb > maxProb) {
                maxProb = currentProb;
                bestClass = c;
              }
            }
            // Set pixel based on best class
            if (bestClass == AppConstants.segmentationFoodClassIndex) {
              // Food class: Copy pixel from resized input (make opaque in mask)
              var originalPixel = resizedForSegmentation.getPixel(x, y);
              segmentationMask.setPixelRgba(x, y, originalPixel.r.toInt(), originalPixel.g.toInt(), originalPixel.b.toInt(), 255);
            } else {
              // Background/Other class: Make transparent in mask
              segmentationMask.setPixelRgba(x, y, 0, 0, 0, 0); // Transparent black
            }
          }
        }
        dev.log("[applySegmentation] Float32 mask created.");

      } else if (_outputType == TensorType.int32 || _outputType == TensorType.int64) {
        // --- Process Int32/Int64 (Class Indices) ---
        dev.log("[applySegmentation] Processing INT32/INT64 output (class indices)...");
        // Check if output shape is [1, H, W, 1] as expected for direct index output
        if (numClasses != 1) {
          dev.log("[ERROR] INT output shape suggests multiple classes per pixel ($_outputShape), but processing logic expects 1 class index per pixel. Cannot proceed.");
          return image;
        }

        List<List<List<List<int>>>> outputIntData;
        try {
          if (_outputType == TensorType.int32) {
            outputIntData = outputTensorBuffer as List<List<List<List<int>>>>;
          } else { // Int64
            // Casting Int64List directly might be tricky. Consider alternatives if issues arise.
            // For now, assume direct cast works after reshape.
            outputIntData = (outputTensorBuffer as List<List<List<List<int>>>>); // May need conversion logic if cast fails
          }
        } catch (e) {
          dev.log("[ERROR] Failed to cast INT output buffer to expected list structure: $e");
          return image;
        }


        // Dimension check after cast
        if (outputIntData.length != 1 || outputIntData[0].length != segHeight || outputIntData[0][0].length != segWidth || outputIntData[0][0][0].length != 1) {
          dev.log("[ERROR] Segmentation INT output dimensions mismatch after inference. Aborting mask creation.");
          return image;
        }

        for (int y = 0; y < segHeight; y++) {
          for (int x = 0; x < segWidth; x++) {
            int predictedClass = outputIntData[0][y][x][0]; // Get class index

            if (predictedClass == AppConstants.segmentationFoodClassIndex) {
              // Food class: Copy pixel from resized input (make opaque in mask)
              var originalPixel = resizedForSegmentation.getPixel(x, y);
              segmentationMask.setPixelRgba(x, y, originalPixel.r.toInt(), originalPixel.g.toInt(), originalPixel.b.toInt(), 255);
            } else {
              // Background/Other class: Make transparent in mask
              segmentationMask.setPixelRgba(x, y, 0, 0, 0, 0);
            }
          }
        }
        dev.log("[applySegmentation] INT32/INT64 mask created.");

      } else {
        dev.log("[ERROR] applySegmentation: Unsupported output type after inference: $_outputType");
        return image; // Return original if type is unexpected
      }

      // --- Post-processing Mask ---
      dev.log("[applySegmentation] Resizing mask back to original dimensions (${originalWidth}x$originalHeight)...");
      // Resize mask back to original image size using linear interpolation
      img.Image finalMask = img.copyResize(
          segmentationMask,
          width: originalWidth,
          height: originalHeight,
          interpolation: img.Interpolation.linear // Linear is good for masks
      );
      dev.log("[applySegmentation] Mask resized.");

      // Apply the final mask to the original input image
      dev.log("[applySegmentation] Applying final mask to original image...");
      // Create a new RGBA image for the result
      img.Image maskedImage = img.Image(width: originalWidth, height: originalHeight, numChannels: 4);

      // Efficiently iterate using bytes if possible
      Uint8List? originalBytes = image.data?.buffer.asUint8List();
      Uint8List? maskBytes = finalMask.data?.buffer.asUint8List();
      Uint8List? maskedBytes = maskedImage.data?.buffer.asUint8List();

      if (originalBytes != null && maskBytes != null && maskedBytes != null && finalMask.numChannels == 4) {
        dev.log("[applySegmentation] Applying mask using direct byte manipulation.");
        int origChannels = image.numChannels; // 3 (RGB) or 4 (RGBA)
        for (int i = 0; i < maskedBytes.length; i += 4) {
          int maskAlphaIndex = i + 3;
          int origPixelIndex = (i ~/ 4) * origChannels;

          if (maskBytes[maskAlphaIndex] > 10) { // If mask pixel is mostly opaque (threshold)
            // Copy RGB from original
            maskedBytes[i] = originalBytes[origPixelIndex];     // R
            maskedBytes[i + 1] = originalBytes[origPixelIndex + 1]; // G
            maskedBytes[i + 2] = originalBytes[origPixelIndex + 2]; // B
            maskedBytes[i + 3] = 255; // Set final alpha to fully opaque
          } else {
            // Mask pixel is transparent, make output pixel transparent black
            maskedBytes[i] = 0;     // R
            maskedBytes[i + 1] = 0; // G
            maskedBytes[i + 2] = 0; // B
            maskedBytes[i + 3] = 0; // Alpha
          }
        }
      } else {
        // Fallback to pixel-by-pixel (slower)
        dev.log("[applySegmentation] Applying mask using getPixel/setPixel fallback.");
        for (int y = 0; y < originalHeight; y++) {
          for (int x = 0; x < originalWidth; x++) {
            var maskPixel = finalMask.getPixel(x, y);
            if (maskPixel.a > 10) { // Check alpha channel of the mask
              var originalPixel = image.getPixel(x, y);
              // Copy original pixel and set alpha to opaque
              maskedImage.setPixelRgba(x, y, originalPixel.r.toInt(), originalPixel.g.toInt(), originalPixel.b.toInt(), 255);
            } else {
              // Set transparent pixel
              maskedImage.setPixelRgba(x, y, 0, 0, 0, 0);
            }
          }
        }
      }


      dev.log("[applySegmentation] Mask applied. Returning segmented image.");
      return maskedImage; // Return the final image with background removed

    } catch (e, stacktrace) {
      dev.log("[ERROR] processing segmentation output or applying mask: $e");
      dev.log("Stacktrace: $stacktrace");
      return image; // Return original image on error during mask creation/application
    }
  }

  // Dispose method (non-static, instance specific - though likely not used if class is all static)
  // Kept for potential future non-static usage, but 'close()' is the primary static way
  void _disposeInterpreter() {
    if (_interpreter != null && _interpreter!.address != 0) {
      _interpreter!.close();
    }
    _interpreter = null;
    _isLoaded = false;
    _inputShape = null;
    _inputType = null;
    _outputShape = null;
    _outputType = null;
    dev.log('[disposeInterpreter] Segmentation interpreter instance disposed (if used).');
  }

  // Static close method - PRIMARY way to dispose the static interpreter
  static void close() {
    _disposeInterpreterStatic();
  }

  // Static helper for disposal
  static void _disposeInterpreterStatic() {
    if (_interpreter != null && _interpreter!.address != 0) {
      _interpreter!.close();
      dev.log('[disposeInterpreterStatic] Static segmentation interpreter closed.');
    } else {
      dev.log('[disposeInterpreterStatic] Static segmentation interpreter was already null or closed.');
    }
    _interpreter = null;
    _isLoaded = false;
    _inputShape = null;
    _inputType = null;
    _outputShape = null;
    _outputType = null;
  }


  // Prepare Input Tensor (Static Helper) - Normalize image to [0, 1]
  static Float32List _prepareInputTensor(img.Image image) {
    // Assumes image is already resized correctly for the model input
    final int W = image.width;
    final int H = image.height;
    var buffer = Float32List(W * H * 3); // RGB format for model
    int pixelIndex = 0;

    dev.log("[_prepareInputTensor] Preparing ${W}x$H image for model input (normalization)...");

    // Prefer direct byte access if available
    Uint8List? bytes = image.data?.buffer.asUint8List();
    int numChannels = image.numChannels;

    if (bytes != null && numChannels >= 3) {
      // dev.log("  Using direct byte access (Channels: $numChannels)");
      for (int i = 0; i < bytes.length; i += numChannels) {
        if (pixelIndex >= buffer.length) break; // Safety break
        buffer[pixelIndex++] = bytes[i] / AppConstants.normalizationFactor;     // R
        buffer[pixelIndex++] = bytes[i + 1] / AppConstants.normalizationFactor; // G
        buffer[pixelIndex++] = bytes[i + 2] / AppConstants.normalizationFactor; // B
        // Skip alpha if numChannels == 4
      }
    } else {
      // Fallback to getPixel
      // dev.log("  Using getPixel fallback (Channels: $numChannels)");
      for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
          if (pixelIndex >= buffer.length) break; // Safety break
          var pixel = image.getPixel(x, y);
          buffer[pixelIndex++] = pixel.r / AppConstants.normalizationFactor;
          buffer[pixelIndex++] = pixel.g / AppConstants.normalizationFactor;
          buffer[pixelIndex++] = pixel.b / AppConstants.normalizationFactor;
        }
        if (pixelIndex >= buffer.length) break; // Safety break
      }
    }

    if (pixelIndex != buffer.length) {
      dev.log("[Warning] _prepareInputTensor: Buffer not completely filled. Index: $pixelIndex, Length: ${buffer.length}");
    }

    dev.log("[_prepareInputTensor] Input tensor prepared.");
    return buffer;
  }
}