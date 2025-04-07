// File: lib/utils/ImagePreprocessing.dart
import 'package:image/image.dart' as img;
import 'constants.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class ImagePreprocessing {
  static tfl.Interpreter? _interpreter;

  /// تحميل نموذج DeepLabV3 من الأصول.
  static Future<void> loadDeepLabModel() async {
    try {
      _interpreter = await tfl.Interpreter.fromAsset(AppConstants.segmentationModelPath);
      print("✅ DeepLabV3 model loaded successfully!");
    } catch (e) {
      print("❌ Error loading DeepLabV3 model: $e");
      rethrow;
    }
  }

  /// دالة applySegmentation: تُطبق نموذج DeepLabV3 لتقسيم الصورة بحيث تُعيد صورة تحتوي على منطقة الطعام فقط.
  static img.Image applySegmentation(img.Image image) {
    if (_interpreter == null) {
      print("لم يتم تحميل نموذج DeepLabV3، إعادة الصورة كما هي.");
      return image;
    }

    // تغيير حجم الصورة لتتناسب مع مدخلات نموذج التقسيم
    int segWidth = AppConstants.segmentationInputWidth;
    int segHeight = AppConstants.segmentationInputHeight;
    img.Image resizedForSegmentation = img.copyResize(image, width: segWidth, height: segHeight);
    print("تم تغيير حجم الصورة لمدخلات نموذج التقسيم: ${segWidth}x${segHeight}");

    // تجهيز بيانات الإدخال: إنشاء مصفوفة ثلاثية الأبعاد [segHeight, segWidth, 3]
    List<List<List<double>>> inputData = List.generate(segHeight, (y) {
      return List.generate(segWidth, (x) {
        int pixel = resizedForSegmentation.getPixel(x, y) as int;
        return [
          ((pixel >> 16) & 0xFF) / AppConstants.normalizationFactor,
          ((pixel >> 8) & 0xFF) / AppConstants.normalizationFactor,
          (pixel & 0xFF) / AppConstants.normalizationFactor,
        ];
      });
    });

    // تجهيز بيانات الإخراج: نفترض أن النموذج يُخرج 21 قناة لكل بكسل
    List<List<List<double>>> outputData = List.generate(segHeight, (y) {
      return List.generate(segWidth, (x) => List.filled(21, 0.0));
    });

    // تشغيل النموذج على بيانات الإدخال
    _interpreter!.run(inputData, outputData);
    print("تم تشغيل نموذج التقسيم على بيانات الإدخال.");

    // إنشاء خريطة تقسيم بحجم الصورة المصغرة
    img.Image segmentationMap = img.Image(
      width: segWidth,
      height: segHeight,
      numChannels: 4,
      backgroundColor: img.ColorInt8.rgba(0, 0, 0, 0),
    );

    // لكل بكسل في الصورة المصغرة، نبحث عن الفئة ذات القيمة الأعلى
    for (int y = 0; y < segHeight; y++) {
      for (int x = 0; x < segWidth; x++) {
        int maxIndex = 0;
        double maxValue = outputData[y][x][0];
        for (int i = 1; i < 21; i++) {
          if (outputData[y][x][i] > maxValue) {
            maxValue = outputData[y][x][i];
            maxIndex = i;
          }
        }
        // إذا كانت الفئة 1 (نفترض أن 1 تمثل الطعام)، نحتفظ بالبكسل من الصورة الأصلية
        if (maxIndex == 1) {
          int origPixel = resizedForSegmentation.getPixel(x, y) as int;
          segmentationMap.setPixel(x, y, origPixel as img.Color);
        } else {
          segmentationMap.setPixel(x, y, img.ColorInt8.rgba(0, 0, 0, 0)); // تعيين البكسل لخلفية شفافة
        }
      }
    }
    print("تم إنشاء خريطة التقسيم.");

    // إعادة تغيير حجم خريطة التقسيم إلى الأبعاد الأصلية للصورة
    img.Image finalSegmented = img.copyResize(segmentationMap, width: image.width, height: image.height);
    print("تم تغيير حجم خريطة التقسيم لتطابق أبعاد الصورة الأصلية: ${finalSegmented.width}x${finalSegmented.height}");
    return finalSegmented;
  }

  /// دالة معالجة نهائية تشمل:
  /// - تطبيق segmentation باستخدام نموذج DeepLabV3.
  /// - تغيير حجم الصورة إلى الأبعاد المطلوبة للنموذج الرئيسي.
  static img.Image preprocessImage(img.Image image, int targetWidth, int targetHeight) {
    img.Image segmentedImage = applySegmentation(image);
    return img.copyResize(segmentedImage, width: targetWidth, height: targetHeight);
  }
}