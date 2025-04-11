// lib/utils/ImagePreprocessing.dart
import 'dart:developer';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'constants.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
// استيراد TensorType مباشرة إذا لزم الأمر, لكنه عادة جزء من tflite_flutter
// import 'package:tflite_flutter/src/tensor.dart'; // <-- قد لا يكون ضرورياً

class ImagePreprocessing {
  static Interpreter? _interpreter;
  static bool _isLoaded = false;
  static List<int>? _inputShape;
  static TensorType? _inputType; // <-- النوع الصحيح
  static List<int>? _outputShape;
  static TensorType? _outputType; // <-- النوع الصحيح

  static Future<void> loadDeepLabModel() async {
    // ... (نفس كود التحميل والتحقق من المرة السابقة باستخدام TensorType) ...
    if (_isLoaded) {
      log("DeepLabV3 model already loaded.");
      return;
    }
    try {
      final interpreterOptions = InterpreterOptions();
      _interpreter = await Interpreter.fromAsset(
          AppConstants.segmentationModelPath,
          options: interpreterOptions);

      var inputTensors = _interpreter!.getInputTensors();
      var outputTensors = _interpreter!.getOutputTensors();

      _inputShape = inputTensors.first.shape;
      _inputType = inputTensors.first.type;   // <-- النوع الصحيح
      _outputShape = outputTensors.first.shape;
      _outputType = outputTensors.first.type; // <-- النوع الصحيح

      _isLoaded = true;
      log("✅ DeepLabV3 model loaded successfully!");
      log('DeepLab Input: Shape=$_inputShape, Type=$_inputType');
      log('DeepLab Output: Shape=$_outputShape, Type=$_outputType');

      if (_inputShape == null || _inputShape!.length != 4 || _inputShape![1] != AppConstants.segmentationInputSize || _inputShape![2] != AppConstants.segmentationInputSize) {
        log("Warning: DeepLab input shape $_inputShape does not match expected [1, ${AppConstants.segmentationInputSize}, ${AppConstants.segmentationInputSize}, 3]");
      }
      // --- استخدام TensorType للمقارنة ---
      if (_outputType != TensorType.int32 && _outputType != TensorType.float32 && _outputType != TensorType.int64) {
        log("Warning: DeepLab output type $_outputType is not the expected INT32, FLOAT32, or INT64. Mask creation might fail.");
      }

    } catch (e) {
      log("❌ Error loading DeepLabV3 model: $e");
      _interpreter = null;
      _isLoaded = false;
    }
  }

  static Future<img.Image> applySegmentation(img.Image image) async {
    // ... (نفس كود بداية الدالة وتجهيز المدخلات والمخرجات من المرة السابقة باستخدام TensorType) ...
    if (!_isLoaded || _interpreter == null || _inputShape == null || _outputShape == null) {
      log("Segmentation skipped: DeepLabV3 model not ready.");
      return image;
    }
    log("Applying DeepLabV3 segmentation...");

    final int segHeight = _inputShape![1];
    final int segWidth = _inputShape![2];

    img.Image resizedForSegmentation = img.copyResize(image, width: segWidth, height: segHeight);
    log("Image resized for segmentation: ${segWidth}x$segHeight");

    Float32List inputBytes = _prepareInputTensor(resizedForSegmentation);
    var inputTensor = inputBytes.buffer.asFloat32List().reshape(_inputShape!);

    Object outputTensor;
    // --- استخدام TensorType للمقارنة ---
    if (_outputType == TensorType.int32 || _outputType == TensorType.int64) {
      outputTensor = List.filled(_outputShape!.reduce((a, b) => a * b), 0).reshape(_outputShape!);
    } else if (_outputType == TensorType.float32) {
      outputTensor = List.filled(_outputShape!.reduce((a, b) => a * b), 0.0).reshape(_outputShape!);
    } else {
      log("Error: Unsupported DeepLab output type: $_outputType");
      return image;
    }


    try {
      log("Running segmentation inference...");
      _interpreter!.run(inputTensor, outputTensor);
      log("Segmentation inference completed.");
    } catch (e) {
      log("Error during segmentation inference: $e");
      return image;
    }

    try {
      log("Creating segmentation mask...");
      img.Image segmentationMask = img.Image(width: segWidth, height: segHeight, numChannels: 4);

      // --- استخدام TensorType للمقارنة ---
      if (_outputType == TensorType.int32 || _outputType == TensorType.int64) {
        // ... (نفس كود معالجة مخرجات int من المرة السابقة) ...
        List<int> outputIntDataFlat;
        // يجب تعديل طريقة الوصول للبيانات بناءً على شكل المخرج الفعلي
        // هذا مثال قد يحتاج لتعديل:
        if (outputTensor is List<List<List<List<int>>>>) {
          outputIntDataFlat = outputTensor.expand((l1) => l1).expand((l2) => l2).expand((l3) => l3).toList();
        } else if (outputTensor is List<List<List<int>>>) { // [1, H, W] ?
          outputIntDataFlat = outputTensor.expand((l1) => l1).expand((l2) => l2).toList();
        }
        else {
          log("Error: Cannot interpret INT32/INT64 output shape: $_outputShape");
          return image;
        }

        for (int i = 0; i < segWidth * segHeight; i++) {
          int y = i ~/ segWidth;
          int x = i % segWidth;
          int predictedClass = outputIntDataFlat[i];
          if (predictedClass == AppConstants.segmentationFoodClassIndex) { // <-- استخدام الثابت الصحيح
            segmentationMask.setPixel(x, y, resizedForSegmentation.getPixel(x,y));
          } else {
            segmentationMask.setPixelRgba(x, y, 0, 0, 0, 0);
          }
        }

      } else if (_outputType == TensorType.float32) {
        // ... (نفس كود معالجة مخرجات float32 من المرة السابقة) ...
        if (_outputShape!.length == 4 && _outputShape![3] == 1) {
          // ... (منطق العتبة threshold) ...
        }
        else if (_outputShape!.length == 4 && _outputShape![3] > 1) {
          // ... (منطق ArgMax) ...
          var outputProbData = outputTensor as List<List<List<List<double>>>>;
          int numClasses = _outputShape![3];
          for (int y = 0; y < segHeight; y++) {
            for (int x = 0; x < segWidth; x++) {
              int bestClass = 0;
              double maxProb = -1.0;
              for (int c = 0; c < numClasses; c++) {
                if (outputProbData[0][y][x][c] > maxProb) {
                  maxProb = outputProbData[0][y][x][c];
                  bestClass = c;
                }
              }
              if (bestClass == AppConstants.segmentationFoodClassIndex) { // <-- استخدام الثابت الصحيح
                segmentationMask.setPixel(x, y, resizedForSegmentation.getPixel(x,y));
              } else {
                segmentationMask.setPixelRgba(x, y, 0, 0, 0, 0);
              }
            }
          }
        } else {
          log("Error: Unexpected float32 output shape for segmentation: $_outputShape");
          return image;
        }
      }

      log("Segmentation mask created.");

      img.Image finalMask = img.copyResize(segmentationMask, width: image.width, height: image.height);
      log("Segmented mask resized back to original dimensions.");

      img.Image maskedImage = img.Image(width: image.width, height: image.height, numChannels: 4);
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          var maskPixelValue = finalMask.getPixel(x, y); // يحصل على كائن Pixel
          // --- الوصول لقناة ألفا مباشرة ---
          int alpha = maskPixelValue.a.toInt(); // <-- التصحيح هنا

          if (alpha > 128) {
            maskedImage.setPixel(x, y, image.getPixel(x, y));
          } else {
            maskedImage.setPixelRgba(x, y, 0, 0, 0, 0);
          }
        }
      }
      log("Original image masked successfully.");
      return maskedImage;

    } catch (e) {
      log("Error processing segmentation output: $e");
      return image;
    }
  }

  /// تجهيز Float32List للصورة (باستخدام الطريقة القديمة للبكسل)
  static Float32List _prepareInputTensor(img.Image image) {
    // ... (نفس الكود من المرة السابقة لاستخدام الطريقة القديمة) ...
    final int W = image.width;
    final int H = image.height;
    var buffer = Float32List(1 * W * H * 3);
    int pixelIndex = 0;

    Uint32List intValues = image.data!.buffer.asUint32List();

    for (int i = 0; i < W * H; i++) {
      int value = intValues[i];
      // نفترض ABGR
      int r = value & 0xFF;
      int g = (value >> 8) & 0xFF;
      int b = (value >> 16) & 0xFF;

      buffer[pixelIndex++] = r / AppConstants.normalizationFactor;
      buffer[pixelIndex++] = g / AppConstants.normalizationFactor;
      buffer[pixelIndex++] = b / AppConstants.normalizationFactor;
    }
    return buffer;
  }

  void close() {
    // ... (نفس كود الإغلاق) ...
    if (_interpreter != null) {
      _interpreter!.close();
      _interpreter = null;
      _isLoaded = false;
      log('Segmentation interpreter closed.');
    }
  }
}