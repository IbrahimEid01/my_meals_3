// lib/utils/DeepLearning.dart
import 'dart:developer';
import 'dart:typed_data'; // <--- تم التأكد من إضافتها
import 'package:image/image.dart' as img;
import 'constants.dart';
import 'ImagePreprocessing.dart'; // <--- تم استيرادها لاستخدامها

class DeepLearning {
  /// تحويل صورة Bitmap مُعادة الحجم إلى Float32List مع التطبيع.
  /// يستخدم الطريقة القديمة للوصول للبكسل.
  static Float32List imageToFloat32List(img.Image image, int inputSize) {
    try {
      if (image.width != inputSize || image.height != inputSize) {
        log('Warning in imageToFloat32List: Image dimensions (${image.width}x${image.height}) != inputSize ($inputSize). Resizing.');
        image = img.copyResize(image, width: inputSize, height: inputSize);
      }

      final int W = image.width;
      final int H = image.height;
      var buffer = Float32List(1 * W * H * 3);
      int pixelIndex = 0;

      // الحصول على البكسلات كمصفوفة int
      // يجب التأكد من أن getBytes يعيد الترتيب الصحيح (RGB أو BGR)
      // الطريقة الأكثر أمانًا هي المرور على البكسلات يدوياً
      Uint32List intValues = image.data!.buffer.asUint32List(); // افتراض تنسيق ABGR أو ARGB
      bool isABGR = image.format == img.Format.uint8 || image.format == img.Format.int8; // قد تحتاج لتعديل حسب النسخة

      pixelIndex = 0; // إعادة تعيين الفهرس
      for (int i = 0; i < W * H; i++) {
        int value = intValues[i];
        // استخراج RGB بالطريقة القديمة (قد تختلف حسب تنسيق image.data)
        // نفترض ARGB
        // int r = (value >> 16) & 0xFF;
        // int g = (value >> 8) & 0xFF;
        // int b = value & 0xFF;

        // نفترض ABGR (شائع في بعض تمثيلات Flutter/Android)
        int r = value & 0xFF;
        int g = (value >> 8) & 0xFF;
        int b = (value >> 16) & 0xFF;

        // التطبيع
        buffer[pixelIndex++] = r / AppConstants.normalizationFactor;
        buffer[pixelIndex++] = g / AppConstants.normalizationFactor;
        buffer[pixelIndex++] = b / AppConstants.normalizationFactor;
      }

      log('Successfully converted image (${W}x${H}) to Float32List (using bitwise).');
      return buffer;
    } catch (e) {
      log('Error converting image to Float32List: $e');
      throw Exception('Failed to convert image to Float32List: $e');
    }
  }


  /// دالة معالجة الصورة الشاملة: تطبيق التقسيم ثم تغيير الحجم ثم التحويل.
  /// (تم تفعيلها وتعديلها)
  static Future<Float32List> loadImageAndPreprocess(
      Uint8List imageBytes,
      int finalTargetSize, // الحجم النهائي المطلوب للنموذج (e.g., 250 or 224)
          {bool applySegmentation = true} // خيار لتفعيل/تعطيل التقسيم
      ) async {
    log('Starting image preprocessing pipeline... Target size: ${finalTargetSize}x$finalTargetSize, Segmentation: $applySegmentation');
    try {
      img.Image? decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        log('Error: Failed to decode image bytes.');
        throw Exception('Failed to decode image');
      }
      log('Image decoded successfully (${decodedImage.width}x${decodedImage.height}).');

      img.Image imageToProcess = decodedImage;

      // --- خطوة التقسيم (إذا كانت مفعلة) ---
      if (applySegmentation) {
        log('Attempting to apply segmentation...');
        try {
          // استدعاء دالة التقسيم المحدثة
          imageToProcess = await ImagePreprocessing.applySegmentation(decodedImage);
          log('Segmentation applied successfully.');
          // يمكنك هنا حفظ الصورة المقسمة للتحقق البصري إذا أردت
          // import 'dart:io';
          // File('path/to/save/segmented_image.png').writeAsBytesSync(img.encodePng(imageToProcess));
        } catch(segError) {
          log('Error applying segmentation: $segError. Proceeding without segmentation.');
          // استمر بالصورة الأصلية في حالة فشل التقسيم
          imageToProcess = decodedImage;
        }
      } else {
        log('Segmentation skipped.');
      }

      // --- خطوة تغيير الحجم النهائية ---
      log('Resizing image to final target size: ${finalTargetSize}x$finalTargetSize...');
      img.Image finalResizedImage = img.copyResize(
          imageToProcess,
          width: finalTargetSize,
          height: finalTargetSize
      );
      log('Image resized successfully.');

      // --- خطوة التحويل إلى Float32List ---
      return imageToFloat32List(finalResizedImage, finalTargetSize);

    } catch (e) {
      log('Error during loadImageAndPreprocess: $e');
      throw Exception('Image processing pipeline failed: $e');
    }
  }
}