import 'dart:developer';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'constants.dart';
import 'ImagePreprocessing.dart'; // Needed for segmentation call

class DeepLearning {

  // *MODIFIED: Re-added center cropping and enhanced logging/error handling*
  /// الشاملة للمعالجة: فك التشفير، القص المركزي 1:1، (اختياري) التقسيم، التحجيم النهائي، ثم التحويل إلى Float32List.
  static Future<Float32List> loadImageAndPreprocess(
      Uint8List imageBytes,
      int finalTargetSize, {
        bool applySegmentation = false, // Default changed to false, be explicit when calling
      }) async {
    log('[loadImageAndPreprocess] Started. Target size: ${finalTargetSize}x$finalTargetSize, Segmentation: $applySegmentation');
    try {
      // 1. Decode Image
      log('[loadImageAndPreprocess] Decoding image...');
      img.Image? decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        log('[ERROR] Failed to decode image bytes.');
        throw Exception('Failed to decode image');
      }
      log('[loadImageAndPreprocess] Image decoded successfully (${decodedImage.width}x${decodedImage.height}).');

      // 2. Center Crop to 1:1 Aspect Ratio
      log('[loadImageAndPreprocess] Applying 1:1 center crop...');
      int size = decodedImage.width < decodedImage.height ? decodedImage.width : decodedImage.height;
      int xOff = (decodedImage.width - size) ~/ 2;
      int yOff = (decodedImage.height - size) ~/ 2;
      img.Image croppedImage = img.copyCrop(decodedImage, x: xOff, y: yOff, width: size, height: size);
      log('[loadImageAndPreprocess] Center crop applied. New dimensions: ${croppedImage.width}x${croppedImage.height}');

      // 3. Apply Segmentation (Optional, applied after crop but before final resize)
      img.Image imageToProcess = croppedImage; // Start with the cropped image
      if (applySegmentation) {
        log('[loadImageAndPreprocess] Attempting to apply segmentation...');
        try {
          // Ensure DeepLab model is loaded before calling applySegmentation
          // Assuming ImagePreprocessing.loadDeepLabModel() is called elsewhere during app init
          if (!ImagePreprocessing.isModelLoaded()) {
            log('[Warning] DeepLab model not loaded, attempting to load now...');
            await ImagePreprocessing.loadDeepLabModel();
            if (!ImagePreprocessing.isModelLoaded()) {
              throw Exception("Failed to load DeepLab model for segmentation.");
            }
          }
          imageToProcess = await ImagePreprocessing.applySegmentation(croppedImage);
          log('[loadImageAndPreprocess] Segmentation applied successfully.');
        } catch (segError, stacktrace) {
          log('[ERROR] Error applying segmentation: $segError.');
          log('Stacktrace: $stacktrace');
          log('[loadImageAndPreprocess] Proceeding without segmentation due to error.');
          // Fallback to using the cropped image without segmentation
          imageToProcess = croppedImage;
        }
      } else {
        log('[loadImageAndPreprocess] Segmentation skipped.');
      }

      // 4. Resize to Final Target Size
      log('[loadImageAndPreprocess] Resizing image to final target size: ${finalTargetSize}x$finalTargetSize...');
      // Use the result from segmentation if applied, otherwise the cropped image
      img.Image finalResizedImage = img.copyResize(imageToProcess, width: finalTargetSize, height: finalTargetSize);
      log('[loadImageAndPreprocess] Image resized successfully.');

      // 5. Convert to Float32List and Normalize
      log('[loadImageAndPreprocess] Converting final image to Float32List...');
      Float32List floatData = _imageToFloat32ListNormalized(finalResizedImage, finalTargetSize);
      log('[loadImageAndPreprocess] Image converted to Float32List successfully.');
      log('[loadImageAndPreprocess] Preprocessing pipeline finished.');
      return floatData;

    } catch (e, stacktrace) {
      log('[CRITICAL ERROR] during loadImageAndPreprocess: $e');
      log('Stacktrace: $stacktrace');
      throw Exception('Image processing pipeline failed: $e');
    }
  }


  /// تحويل صورة Bitmap إلى Float32List مع تطبيع القيم إلى [0, 1].
  /// Assumes image is already resized to the correct inputSize.
  static Float32List _imageToFloat32ListNormalized(img.Image image, int inputSize) {
    log('[_imageToFloat32ListNormalized] Starting conversion for ${inputSize}x$inputSize image.');
    try {
      // Double-check dimensions (should already be correct)
      if (image.width != inputSize || image.height != inputSize) {
        log('[Warning] Image dimensions (${image.width}x${image.height}) do not match inputSize ($inputSize) in _imageToFloat32ListNormalized. Resizing again.');
        image = img.copyResize(image, width: inputSize, height: inputSize);
      }

      final int W = image.width;
      final int H = image.height;
      // Create buffer for RGB channels
      var buffer = Float32List(W * H * 3);
      int pixelIndex = 0; // Index for the buffer

      // Check if image data is directly accessible as bytes
      if (image.data != null) {
        log('[_imageToFloat32ListNormalized] Using image.data for pixel access.');
        Uint8List? imageBytes = image.data?.buffer.asUint8List();
        int numChannels = image.numChannels; // Get actual number of channels
        if (imageBytes == null) {
          throw Exception("Image data buffer is null");
        }
        if (numChannels < 3) {
          throw Exception("Image must have at least 3 channels (RGB), found $numChannels");
        }

        for (int i = 0; i < imageBytes.length; i += numChannels) {
          // Read RGB, skip Alpha if present (numChannels == 4)
          buffer[pixelIndex++] = imageBytes[i] / AppConstants.normalizationFactor;     // R
          buffer[pixelIndex++] = imageBytes[i + 1] / AppConstants.normalizationFactor; // G
          buffer[pixelIndex++] = imageBytes[i + 2] / AppConstants.normalizationFactor; // B
        }
      } else {
        // Fallback to getPixel (might be slower)
        log('[_imageToFloat32ListNormalized] Using getPixel fallback for pixel access.');
        for (int y = 0; y < H; y++) {
          for (int x = 0; x < W; x++) {
            var pixel = image.getPixel(x, y);
            // Normalize RGB values
            buffer[pixelIndex++] = pixel.r / AppConstants.normalizationFactor;
            buffer[pixelIndex++] = pixel.g / AppConstants.normalizationFactor;
            buffer[pixelIndex++] = pixel.b / AppConstants.normalizationFactor;
          }
        }
      }


      log('[_imageToFloat32ListNormalized] Successfully converted image (${W}x${H}) to Float32List.');
      return buffer;

    } catch (e, stacktrace) {
      log('[ERROR] converting image to Float32List: $e');
      log('Stacktrace: $stacktrace');
      throw Exception('Failed to convert image to Float32List: $e');
    }
  }

// Removed the old imageToFloat32List as the new one replaces it.
// Removed the old loadImageAndPreprocess skeleton as the new one replaces it.
}