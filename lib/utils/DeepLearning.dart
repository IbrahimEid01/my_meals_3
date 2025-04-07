// File: lib/utils/deep_learning.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'ImagePreprocessing.dart';
import 'constants.dart';

class DeepLearning {
  /// تحويل الصورة المُعالَجة إلى Float32List بحيث تصبح جاهزة كمدخل للنموذج.
  /// تُفترض أن تكون الصورة بالحجم المحدد (مثلاً 300×300) وقيمها مطبعة بين 0 و1.
  static Float32List convertImageToFloat32List(img.Image image) {
    final int width = image.width;
    final int height = image.height;
    final int channels = 3; // نستخدم RGB
    final int numPixels = width * height * channels;

    // الحصول على بيانات الصورة باستخدام getBytes() (يُرجى التأكد من أن الصورة تحتوي على بيانات RGB)
    final Uint8List rgbBytes = image.getBytes();
    Float32List buffer = Float32List(numPixels);

    for (int i = 0; i < numPixels; i++) {
      buffer[i] = rgbBytes[i] / AppConstants.normalizationFactor;
    }
    return buffer;
  }

  /// دالة alias لتحويل الصورة إلى Float32List.
  static Float32List loadImageAsFloatList(img.Image image, int width, int height) {
    // تغيير حجم الصورة إلى الأبعاد المطلوبة قبل التحويل
    img.Image resized = img.copyResize(image, width: width, height: height);
    return convertImageToFloat32List(resized);
  }

  /// دالة شاملة لمعالجة الصورة:
  /// - تفكيك الـ Uint8List إلى صورة باستخدام مكتبة image.
  /// - تمرير الصورة عبر عملية المعالجة (Segmentation + Resize) باستخدام ImagePreprocessing.
  /// - تحويل الصورة المُعالَجة إلى Float32List.
  static Float32List processImage(Uint8List imageBytes) {
    img.Image? decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) {
      throw Exception('Failed to decode image');
    }
    // معالجة الصورة: تطبيق segmentation وإعادة تغيير الحجم إلى أبعاد النموذج الرئيسي
    img.Image processedImage = ImagePreprocessing.preprocessImage(
      decodedImage,
      AppConstants.classificationInputWidth, // نستخدم هنا أبعاد نموذج التصنيف (يمكن تغييرها حسب الحاجة)
      AppConstants.classificationInputHeight,
    );
    return convertImageToFloat32List(processedImage);
  }
}