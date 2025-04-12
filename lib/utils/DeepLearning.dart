import 'dart:developer';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'constants.dart';
import 'ImagePreprocessing.dart';

class DeepLearning {
  /// تحويل صورة Bitmap إلى Float32List مع التطبيع.
  static Float32List imageToFloat32List(img.Image image, int inputSize) {
    try {
      if (image.width != inputSize || image.height != inputSize) {
        log('Warning in imageToFloat32List: Image dimensions (${image.width}x${image.height}) != inputSize ($inputSize). Resizing.');
        image = img.copyResize(image, width: inputSize, height: inputSize);
      }
      final int W = image.width;
      final int H = image.height;
      var buffer = Float32List(W * H * 3);
      int pixelIndex = 0;
      for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
          var pixel = image.getPixel(x, y);
          int r = pixel.r.toInt();
          int g = pixel.g.toInt();
          int b = pixel.b.toInt();
          buffer[pixelIndex++] = r / AppConstants.normalizationFactor;
          buffer[pixelIndex++] = g / AppConstants.normalizationFactor;
          buffer[pixelIndex++] = b / AppConstants.normalizationFactor;
        }
      }
      log('Successfully converted image (${W}x${H}) to Float32List.');
      return buffer;
    } catch (e) {
      log('Error converting image to Float32List: $e');
      throw Exception('Failed to convert image to Float32List: $e');
    }
  }

  /// معالجة الصورة الشاملة: فك التشفير، (اختياري) التقسيم باستخدام DeepLabV3، تغيير الحجم، ثم التحويل إلى Float32List.
  static Future<Float32List> loadImageAndPreprocess(
      Uint8List imageBytes,
      int finalTargetSize, {
        bool applySegmentation = true,
      }) async {
    log('Starting image preprocessing pipeline... Target size: ${finalTargetSize}x$finalTargetSize, Segmentation: $applySegmentation');
    try {
      img.Image? decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        log('Error: Failed to decode image bytes.');
        throw Exception('Failed to decode image');
      }
      log('Image decoded successfully (${decodedImage.width}x${decodedImage.height}).');
      img.Image imageToProcess = decodedImage;

      if (applySegmentation) {
        log('Attempting to apply segmentation using DeepLabV3...');
        try {
          imageToProcess = await ImagePreprocessing.applySegmentation(decodedImage);
          log('Segmentation applied successfully.');
        } catch (segError) {
          log('Error applying segmentation: $segError. Proceeding with original image.');
          imageToProcess = decodedImage;
        }
      } else {
        log('Segmentation skipped.');
      }

      log('Resizing image to final target size: ${finalTargetSize}x$finalTargetSize...');
      img.Image finalResizedImage = img.copyResize(imageToProcess, width: finalTargetSize, height: finalTargetSize);
      log('Image resized successfully.');

      Float32List floatData = imageToFloat32List(finalResizedImage, finalTargetSize);
      log('Image converted to Float32List successfully.');
      return floatData;
    } catch (e) {
      log('Error during loadImageAndPreprocess: $e');
      throw Exception('Image processing pipeline failed: $e');
    }
  }
}