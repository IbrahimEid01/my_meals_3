import 'dart:developer' as dev; // إعطاء اسم مستعار لـ log من dart:developer
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'constants.dart'; // تأكد من أن هذا المسار صحيح
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:math' hide log; // إخفاء log من dart:math لتجنب التعارض

class ImagePreprocessing {
  // المتغيرات static لأن هذا Class يتعامل مع Model واحد يتم تحميله مرة واحدة للتطبيق
  static Interpreter? _interpreter;
  static bool _isLoaded = false;
  static List<int>? _inputShape;
  static TensorType? _inputType;
  static List<int>? _outputShape;
  static TensorType? _outputType;

  // دالة تحميل نموذج DeepLabV3 (static لأنها تتعامل مع المتغيرات static)
  static Future<void> loadDeepLabModel() async {
    // إضافة تحقق للتأكد من أن المترجم لم يتم تحميله بالفعل
    if (_isLoaded && _interpreter != null && _interpreter!.address != 0) {
      dev.log("DeepLabV3 model already loaded.");
      return;
    }
    try {
      final interpreterOptions = InterpreterOptions();
      // يمكنك إضافة delegates هنا لتحسين الأداء (CPU, GPU, NNAPI)
      // interpreterOptions.addDelegate(GpuDelegateV2()); // مثال لـ GPU

      // تحميل النموذج من الـ assets
      _interpreter = await Interpreter.fromAsset(AppConstants.segmentationModelPath, options: interpreterOptions);

      // التحقق من أن المترجم تم إنشاؤه بنجاح
      if (_interpreter == null || _interpreter!.address == 0) {
        dev.log("❌ Error loading DeepLabV3 model: Interpreter not created.");
        // لا حاجة لاستدعاء _disposeInterpreter هنا لأن المترجم لم يتم إنشاؤه بنجاح بعد
        return; // الخروج إذا فشل الإنشاء
      }


      var inputTensors = _interpreter!.getInputTensors();
      var outputTensors = _interpreter!.getOutputTensors();

      if (inputTensors.isEmpty || outputTensors.isEmpty) {
        dev.log("❌ Error loading DeepLabV3 model: No input or output tensors found.");
        _disposeInterpreterStatic(); // استدعاء الدالة المساعدة static للتخلص
        return; // الخروج
      }
      if (inputTensors.length > 1 || outputTensors.length > 1) {
        dev.log("Warning: DeepLabV3 model has more than one input or output tensor. Using the first one.");
      }

      // حفظ شكل ونوع المدخل والمخرج الأول
      _inputShape = inputTensors.first.shape;
      _inputType = inputTensors.first.type;
      _outputShape = outputTensors.first.shape;
      _outputType = outputTensors.first.type;

      _isLoaded = true; // تم التحميل بنجاح حتى هذه النقطة
      dev.log("✅ DeepLabV3 model loaded successfully!");
      dev.log('DeepLab Input: Shape=$_inputShape, Type=$_inputType');
      dev.log('DeepLab Output: Shape=$_outputShape, Type=$_outputType');

      // تحققات لشكل ونوع المدخل والمخرجات المتوقعة بناءً على تحليل الـ PDF وسجلات التشغيل
      // التحقق من شكل المدخلات: [1, segmentationInputSize, segmentationInputSize, 3]
      if (_inputShape == null || _inputShape!.length != 4 || _inputShape![0] != 1 || _inputShape![1] != AppConstants.segmentationInputSize || _inputShape![2] != AppConstants.segmentationInputSize || _inputShape![3] != 3) {
        dev.log("Warning: DeepLab input shape $_inputShape does not match expected [1, ${AppConstants.segmentationInputSize}, ${AppConstants.segmentationInputSize}, 3]");
      }
      // التحقق من شكل المخرج كما يظهر في سجل التشغيل: [1, H, W, 151]
      if (_outputShape == null || _outputShape!.length != 4 || _outputShape![0] != 1 || _outputShape![3] != 151) {
        dev.log("Warning: DeepLab output shape $_outputShape does not match expected [1, H, W, 151]");
      }
      // التحقق من نوع المخرج كما يظهر في سجل التشغيل: FLOAT32
      if (_outputType != TensorType.float32) {
        dev.log("Warning: DeepLab output type $_outputType does not match expected FLOAT32.");
      }


    } catch (e) {
      dev.log("❌ Error loading DeepLabV3 model: $e"); // تسجيل أي خطأ يحدث أثناء التحميل
      _disposeInterpreterStatic(); // استدعاء الدالة المساعدة static للتخلص في حالة الفشل
    }
  }

  // دالة تطبيق التقسيم (static لأنها تستخدم المترجم والبيانات الثابتة)
  static Future<img.Image> applySegmentation(img.Image image) async {
    // التحقق من أن المترجم جاهز قبل الاستخدام
    if (!_isLoaded || _interpreter == null || _interpreter!.address == 0 || _inputShape == null || _outputShape == null || _outputType == null) {
      dev.log("Segmentation skipped: DeepLabV3 model not ready or failed to load.");
      return image; // العودة بالصورة الأصلية إذا لم يكن النموذج جاهزاً
    }
    dev.log("Applying DeepLabV3 segmentation...");

    // استخلاص الأبعاد المتوقعة من شكل المدخلات والمخرجات المحفوظة
    final int segHeight = _inputShape![1]; // المتوقع 513
    final int segWidth = _inputShape![2];   // المتوقع 513
    final int numClasses = _outputShape![3]; // المتوقع 151

    // التحقق للتأكد من أن شكل المخرج هو [1, H, W, C] كما يتوقعه الكود اللاحق
    if (_outputShape!.length != 4 || _outputShape![0] != 1 || _outputShape![3] <= 0) {
      dev.log("Error: DeepLab output shape $_outputShape is not in expected [1, H, W, C] format for segmentation processing.");
      return image; // العودة بالصورة الأصلية
    }

    // إعادة تحجيم الصورة لمدخلات نموذج DeepLabV3
    img.Image resizedForSegmentation = img.copyResize(image, width: segWidth, height: segHeight);
    dev.log("Image resized for segmentation: ${segWidth}x$segHeight");

    // تحضير المدخلات (تحويل الصورة إلى Float32List مع التطبيع)
    Float32List inputBytes = _prepareInputTensor(resizedForSegmentation);
    // إعادة تشكيل المدخل للشكل المتوقع [1, 513, 513, 3]
    var inputTensor = inputBytes.buffer.asFloat32List().reshape(_inputShape!);

    // تجهيز مخزن للمخرجات
    int outputFlatSize = 1 * segHeight * segWidth * numClasses; // الحجم المسطح الكلي للمخرجات
    Object outputTensorBuffer; // متغير لحمل المخزن (استخدام Object صحيح هنا لأنه سيحمل نوع TypedData معين)
    List<int> outputExpectedShape = [1, segHeight, segWidth, numClasses]; // الشكل المتعدد الأبعاد المتوقع للمخرجات


    // إنشاء مخزن المخرجات بناءً على نوع المخرج المتوقع
    if (_outputType == TensorType.float32) {
      // إنشاء Float32List بالحجم المسطح وإعادة تشكيلها للشكل المتعدد الأبعاد المتوقع [1, 513, 513, 151]
      outputTensorBuffer = Float32List(outputFlatSize).reshape(outputExpectedShape); // *** التعديل هنا: إضافة reshape ***
    } else if (_outputType == TensorType.int32) {
      // إنشاء Int32List بالحجم المسطح وإعادة تشكيلها للشكل المتعدد الأبعاد المتوقع
      outputTensorBuffer = Int32List(outputFlatSize).reshape(outputExpectedShape); // *** التعديل هنا: إضافة reshape ***
    } else if (_outputType == TensorType.int64) {
      // إنشاء Int64List بالحجم المسطح وإعادة تشكيلها للشكل المتعدد الأبعاد المتوقع
      outputTensorBuffer = Int64List(outputFlatSize).reshape(outputExpectedShape); // *** التعديل هنا: إضافة reshape ***
    }
    else {
      dev.log("Error: Unsupported DeepLab output type for mask creation: $_outputType"); // تسجيل الخطأ بنظام logging جديد
      return image; // العودة بالصورة الأصلية
    }


    try {
      dev.log("Running segmentation inference..."); // تسجيل بدء الاستنتاج

      // --- إضافة Logging قبل التشغيل لمتابعة شكل المخزن (تم تصحيح أخطاء الكومبايلر وإضافة تفاصيل) ---
      dev.log("Segmentation output buffer type before run: ${outputTensorBuffer.runtimeType}");
      if (outputTensorBuffer is TypedData) {
        // للوصول إلى length بشكل آمن على TypedData، نستخدم buffer ثم getView
        // هذا يعطي طول المخزن بالبايتات، أو يمكن استخدام length على getView الناتج
        dev.log("Segmentation output buffer length (bytes) before run: ${(outputTensorBuffer as TypedData).buffer.lengthInBytes}"); // *** تم تصحيح خطأ التجميع ***
        dev.log("Segmentation output buffer element size (bytes): ${(outputTensorBuffer as TypedData).elementSizeInBytes}");
        // محاولة طباعة شكل المخزن بعد إعادة التشكيل (قد يعتمد على implementation المكتبة)
        try {
          // الوصول لخاصية 'shape' إذا كانت موجودة بعد reshape باستخدام dynamic cast
          // هذا قد لا يعمل في كل البيئات/الإصدارات، لذا هو داخل try/catch
          dev.log("Segmentation output buffer shape property before run: ${(outputTensorBuffer as dynamic).shape}"); // تم تصحيح خطأ التجميع
        } catch (e) {
          dev.log("Could not access shape property on output buffer: $e"); // تسجيل الخطأ بنظام logging جديد
        }
      } else {
        dev.log("Segmentation output buffer is not TypedData."); // تسجيل الخطأ بنظام logging جديد
      }
      dev.log("Segmentation output buffer expected flat size: $outputFlatSize"); // تسجيل الحجم المسطح المتوقع
      dev.log("Segmentation output buffer expected multi-dimensional shape: $outputExpectedShape"); // تسجيل الشكل المتعدد الأبعاد المتوقع
      // --- نهاية Logging ---

      // تشغيل الاستنتاج - تمرير المدخلات والمخزن المُعاد تشكيله
      _interpreter!.run(inputTensor, outputTensorBuffer);
      dev.log("Segmentation inference completed."); // تسجيل اكتمال الاستنتاج

    } catch (e) {
      dev.log("Error during segmentation inference: $e"); // تسجيل أي خطأ يحدث أثناء الاستنتاج
      // بناءً على السجل السابق، المشكلة كانت Invalid argument(s): Output object shape mismatch
      return image; // العودة بالصورة الأصلية عند الفشل
    }

    try {
      dev.log("Creating segmentation mask..."); // تسجيل بدء إنشاء القناع
      img.Image segmentationMask = img.Image(width: segWidth, height: segHeight, numChannels: 4); // إنشاء صورة قناع RGBA

      // التعامل مع المخرجات بناءً على النوع مع الكاست الصريح إلى الشكل المتعدد الأبعاد المتوقع
      if (_outputType == TensorType.float32) {
        // نموذج يخرج احتمالات الفئة لكل بكسل [1, H, W, C]
        // الكاست الصريح إلى الشكل المتعدد الأبعاد المتوقع بعد reshape
        // إذا نجحت عملية reshape، يجب أن يكون المخزن الآن متاحاً بهذا الشكل المتداخل
        var outputProbData = outputTensorBuffer as List<List<List<List<double>>>>; // *** الكاست هنا يتوقع شكل متداخل بعد reshape ***

        // التحقق من الأبعاد بعد الكاست للتأكد من أنها منطقية
        if (outputProbData.length != 1 ||
            outputProbData[0].length != segHeight ||
            outputProbData[0][0].length != segWidth ||
            outputProbData[0][0][0].length != numClasses) {
          dev.log("Error: Segmentation output data dimensions mismatch after multi-dimensional cast. Actual dimensions may differ."); // تسجيل الخطأ بنظام logging جديد
          return image; // العودة بالصورة الأصلية
        }

        // حلقات متداخلة على الأبعاد لاستخراج أفضل فئة لكل بكسل
        for (int y = 0; y < segHeight; y++) {
          for (int x = 0; x < segWidth; x++) {
            int bestClass = -1;
            double maxProb = -double.infinity; // استخدام سالب ما لا نهاية للعثور على أكبر احتمال

            // حلقة على الفئات للوصول إلى الاحتمالات باستخدام الفهرسة المتعددة الأبعاد
            for (int c = 0; c < numClasses; c++) {
              // الوصول إلى الاحتمال باستخدام الفهرسة المتعددة الأبعاد [batch_index][y][x][class_index]
              // بما أن batch_index = 0، الفهرس هو [0][y][x][c]
              double currentProb = outputProbData[0][y][x][c]; // *** الوصول هنا باستخدام الفهرسة المتعددة الأبعاد ***
              if (currentProb > maxProb) {
                maxProb = currentProb;
                bestClass = c;
              }
            }

            // بعد إيجاد الفئة الأكثر احتمالاً لهذا البكسل
            // إذا كانت أفضل فئة هي فئة الطعام (باستخدام الفهرس المحدد)، احتفظ بلون البكسل الأصلي
            if (bestClass == AppConstants.segmentationFoodClassIndex) {
              // تأكد مرة أخرى أن الفهرس في AppConstants.segmentationFoodClassIndex هو فئة الطعام فعلاً!
              // (تم شرح كيفية التحقق من هذا سابقاً باستخدام Netron أو التجربة)
              segmentationMask.setPixel(x, y, resizedForSegmentation.getPixel(x, y));
            } else {
              // بكسل الخلفية أو فئة أخرى - اجعله شفافاً تماماً في القناع
              segmentationMask.setPixelRgba(x, y, 0, 0, 0, 0);
            }
          }
        }
      }
      // التعامل مع مخرجات INT32/INT64 (غالباً ما تكون لشكل [1, H, W, 1] حيث القيمة هي فهرس الفئة)
      else if (_outputType == TensorType.int32 || _outputType == TensorType.int64) {
        // التحقق من أن شكل المخرج مناسب لهذا النوع (غالباً [1, H, W, 1])
        if (_outputShape!.length != 4 || _outputShape![0] != 1 || _outputShape![3] != 1) {
          dev.log("Error: Segmentation INT output shape $_outputShape is not in expected [1, H, W, 1] format for direct index output."); // تسجيل الخطأ بنظام logging جديد
          return image; // العودة بالصورة الأصلية
        }

        List<List<List<List<int>>>> outputIntData;
        if (_outputType == TensorType.int32) {
          // الكاست الصريح إلى الشكل المتعدد الأبعاد المتوقع بعد reshape
          outputIntData = outputTensorBuffer as List<List<List<List<int>>>>; // *** الكاست هنا يتوقع شكل متداخل بعد reshape ***
        } else { // TensorType.int64
          // الكاست الصريح إلى الشكل المتعدد الأبعاد ثم تحويل Int64 إلى Int في القائمة المتداخلة
          // هذه العملية معقدة وقد تفشل بناءً على طريقة عمل reshape
          // قد يكون التعامل معها كقائمة مسطحة بعد run أسهل إذا كانت reshape تسبب مشاكل
          dev.log("Warning: INT64 segmentation output processing might be complex with reshape. Consider processing as flattened list if issues arise."); // تسجيل التحذير بنظام logging جديد
          // مثال لكيفية معالجة Int64 كقائمة مسطحة بعد تشغيل run (إذا فشلت الطريقة المتداخلة)
          // Int64List flatBuffer = (outputTensorBuffer as TypedData).buffer.asInt64List();
          // int predictedClass = flatBuffer[y * segWidth + x]; // مثال للفهرسة المسطحة عندما C=1
          // ... بقية المنطق
          return image; // العودة بالصورة مؤقتاً إذا كانت معالجة INT64 المتداخلة معقدة
        }

        // التحقق من الأبعاد بعد الكاست للتأكد من أنها منطقية
        if (outputIntData.length != 1 ||
            outputIntData[0].length != segHeight ||
            outputIntData[0][0].length != segWidth ||
            outputIntData[0][0][0].length != 1) {
          dev.log("Error: Segmentation INT output data dimensions mismatch after multi-dimensional cast. Actual dimensions may differ."); // تسجيل الخطأ بنظام logging جديد
          return image; // العودة بالصورة الأصلية
        }

        // حلقات متداخلة للوصول إلى فهرس الفئة لكل بكسل
        for (int y = 0; y < segHeight; y++) {
          for (int x = 0; x < segWidth; x++) {
            // الوصول إلى فهرس الفئة باستخدام الفهرسة المتعددة الأبعاد [batch_index][y][x][0]
            int predictedClass = outputIntData[0][y][x][0]; // *** الوصول هنا باستخدام الفهرسة المتعددة الأبعاد (C=1) ***

            if (predictedClass == AppConstants.segmentationFoodClassIndex) {
              // إذا كان فهرس الفئة هو فئة الطعام، انسخ البكسل من الصورة المعاد تحجيمها
              segmentationMask.setPixel(x, y, resizedForSegmentation.getPixel(x, y));
            } else {
              // بكسل خلفية أو فئة أخرى - اجعله شفافاً في القناع
              segmentationMask.setPixelRgba(x, y, 0, 0, 0, 0);
            }
          }
        }

      } // نهاية التعامل مع INT32/INT64
      else {
        dev.log("Error: Fallback - Unsupported DeepLab output type after inference: $_outputType"); // تسجيل الخطأ بنظام logging جديد
        return image; // العودة بالصورة الأصلية
      }


      dev.log("Segmentation mask created."); // تسجيل إنشاء القناع

      // إعادة تحجيم القناع إلى الأبعاد الأصلية للصورة باستخدام interpolation
      // استخدام interpolation.linear مناسب للماسكات
      img.Image finalMask = img.copyResize(segmentationMask, width: image.width, height: image.height, interpolation: img.Interpolation.linear);
      dev.log("Segmented mask resized back to original dimensions."); // تسجيل إعادة التحجيم

      // تطبيق القناع على الصورة الأصلية باستخدام معالجة Bytes (تم تحسينها للأداء)
      img.Image maskedImage = img.Image(width: image.width, height: image.height, numChannels: 4); // إنشاء صورة مخرجة RGBA
      Uint8List originalBytes = image.getBytes(); // الحصول على بيانات البكسل الأصلية كـ bytes
      Uint8List maskBytes = finalMask.getBytes(); // الحصول على بيانات بكسل القناع كـ bytes (RGBA)

      int originalBytesPerPixel = image.numChannels; // عدد قنوات الصورة الأصلية (عادة 3 أو 4)
      int maskBytesPerPixel = finalMask.numChannels; // عدد قنوات القناع (يجب أن يكون 4 لـ RGBA)
      int maskedBytesPerPixel = 4; // عدد قنوات الصورة المقنّعة التي سننشئها (RGBA)

      Uint8List maskedBytes = Uint8List(image.width * image.height * maskedBytesPerPixel); // مخزن للبيانات المقنّعة
      int originalPixelIndex = 0; // فهرس البكسل الحالي في بيانات الصورة الأصلية
      int maskPixelIndex = 0; // فهرس البكسل الحالي في بيانات القناع
      int maskedPixelIndex = 0; // فهرس البكسل الحالي في بيانات الصورة المقنّعة

      // حلقة على جميع البكسلات لتطبيق القناع
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          // الوصول لقناة ألفا في القناع (القناة الأخيرة في RGBA)
          // إضافة تحقق للحدود لتجنب قراءة خارج نطاق القائمة
          if (maskPixelIndex + maskBytesPerPixel <= maskBytes.length) {
            int alpha = maskBytes[maskPixelIndex + maskBytesPerPixel - 1]; // قناة ألفا هي البايت الأخير للبكسل في RGBA

            // إذا كانت قناة ألفا في القناع أعلى من عتبة معينة (مثلاً 10 من 255)، اعتبر البكسل جزءاً من الكائن المقسّم
            if (alpha > 10) { // استخدام عتبة صغيرة للسماح ببعض التدرج في القناع المعاد تحجيمه
              // انسخ بيانات RGB من الصورة الأصلية
              // إضافة تحقق للحدود لتجنب قراءة خارج نطاق الصورة الأصلية
              if (originalPixelIndex + 3 <= originalBytes.length) { // نحتاج 3 بايتات لـ RGB
                maskedBytes[maskedPixelIndex++] = originalBytes[originalPixelIndex++]; // R
                maskedBytes[maskedPixelIndex++] = originalBytes[originalPixelIndex++]; // G
                maskedBytes[maskedPixelIndex++] = originalBytes[originalPixelIndex++]; // B
                // قم بتعيين ألفا لـ 255 (معتم تماماً) في الصورة المقنّعة
                maskedBytes[maskedPixelIndex++] = 255; // Alpha (معتم)

                // إذا كانت الصورة الأصلية RGBA (bytesPerPixel == 4)، تخطي بايت ألفا الخاص بها أيضاً
                if (originalBytesPerPixel == 4) {
                  if (originalPixelIndex + 1 <= originalBytes.length) { // تحقق من الحدود قبل تخطي ألفا
                    originalPixelIndex++; // تخطي بايت ألفا في الصورة الأصلية
                  } else {
                    dev.log("Warning: Original image bytes unexpected end while skipping alpha. Index: $originalPixelIndex, Length: ${originalBytes.length}"); // تسجيل تحذير
                    // في حالة غير متوقعة جداً، حاول التقدم للفهرس النهائي لتجنب حلقة لا نهائية
                    originalPixelIndex = originalBytes.length;
                  }
                }

              } else { // حالة حدود غير متوقعة في الصورة الأصلية أثناء محاولة قراءة RGB
                dev.log("Warning: Original image bytes unexpected end while copying RGB. Index: $originalPixelIndex, Length: ${originalBytes.length}"); // تسجيل تحذير
                // اجعل البكسل شفافاً في الصورة المقنّعة
                maskedBytes[maskedPixelIndex++] = 0; maskedBytes[maskedPixelIndex++] = 0; maskedBytes[maskedPixelIndex++] = 0; maskedBytes[maskedPixelIndex++] = 0; // بكسل شفاف تماماً
                // حاول التقدم بفهرس الصورة الأصلية لتجنب التعثر (بقدر ما تبقى من بايتات)
                originalPixelIndex += (originalBytes.length - originalPixelIndex); // التقدم إلى نهاية القائمة
              }
            } else {
              // البكسل هو خلفية (ألفا منخفضة) - اجعله شفافاً تماماً في الصورة المقنّعة
              maskedBytes[maskedPixelIndex++] = 0; // R
              maskedBytes[maskedPixelIndex++] = 0; // G
              maskedBytes[maskedPixelIndex++] = 0; // B
              maskedBytes[maskedPixelIndex++] = 0; // Alpha (شفاف تماماً)
              // تقدم بفهرس الصورة الأصلية للوصول للبكسل التالي
              originalPixelIndex += originalBytesPerPixel;
            }
          } else { // حالة حدود غير متوقعة في بيانات القناع
            dev.log("Warning: Mask bytes unexpected end while accessing pixel. Index: $maskPixelIndex, Length: ${maskBytes.length}"); // تسجيل تحذير
            // اجعل البكسل شفافاً في الصورة المقنّعة
            maskedBytes[maskedPixelIndex++] = 0; maskedBytes[maskedPixelIndex++] = 0; maskedBytes[maskedPixelIndex++] = 0; maskedBytes[maskedPixelIndex++] = 0; // بكسل شفاف تماماً
            // تقدم بفهرس الصورة الأصلية للوصول للبكسل التالي (بقدر ما تبقى من بايتات)
            originalPixelIndex += (originalBytes.length - originalPixelIndex); // التقدم إلى نهاية القائمة
          }
          maskPixelIndex += maskBytesPerPixel; // انتقل للبكسل التالي في بيانات القناع
        }
      }

      // إنشاء صورة جديدة من بيانات البكسل المقنّعة (RGBA)
      img.Image finalMaskedImage = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: maskedBytes.buffer, // استخدام buffer من Uint8List
        numChannels: 4, // RGBA
      );

      dev.log("Original image masked successfully."); // تسجيل نجاح تطبيق القناع
      return finalMaskedImage; // إرجاع الصورة بعد تطبيق القناع

    } catch (e) {
      dev.log("Error processing segmentation output or applying mask: $e"); // تسجيل أي خطأ يحدث أثناء المعالجة اللاحقة
      // في حالة أي خطأ أثناء المعالجة اللاحقة (بعد الاستنتاج الناجح)، نرجع الصورة الأصلية
      return image;
    }
  }

  // دالة مساعدة للتخلص من الـ interpreter (تم إزالة static لحل خطأ النطاق)
  // هذه الدالة يجب أن تكون دالة عادية (instance method) للوصول إلى _interpreter الخاص بالفئة
  void _disposeInterpreter() { // *** تم إزالة static هنا لحل خطأ التجميع المتعلق بنطاق _interpreter ***
    // تحقق من أن المترجم موجود وصالح قبل محاولة إغلاقه
    if (_interpreter != null && _interpreter!.address != 0) {
      _interpreter!.close();
      //dev.log('Segmentation interpreter disposed using close().'); // log هنا قد تسبب مشكلة إذا استدعيت بعد dispose فعلياً
    }
    _interpreter = null; // تعيين لـ null دائماً بعد المحاولة لتجنب استخدام مؤشر غير صالح
    _isLoaded = false; // إعادة تعيين حالة التحميل
    _inputShape = null; // إعادة تعيين الأشكال والأنواع المحفوظة
    _inputType = null;
    _outputShape = null;
    _outputType = null;
    dev.log('Segmentation interpreter disposed.'); // تسجيل الإغلاق
  }

  // دالة close() العامة لاستدعائها من خارج الفئة (تستدعي دالة dispose المساعدة)
  // هذه الدالة static لأنها تستدعى من خارج الفئة ولا تتعامل مع كائن معين
  static void close() { // *** تم إضافة static هنا لتصحيح طريقة الاستدعاء الخارجية ***
    _disposeInterpreterStatic(); // استدعاء الدالة المساعدة static
  }

  // دالة مساعدة static للتخلص من الـ interpreter في حالة الاستخدام الثابت
  static void _disposeInterpreterStatic() {
    if (_interpreter != null && _interpreter!.address != 0) {
      _interpreter!.close();
    }
    _interpreter = null;
    _isLoaded = false;
    _inputShape = null;
    _inputType = null;
    _outputShape = null;
    _outputType = null;
    dev.log('Segmentation interpreter disposed (static).');
  }


  // دالة تحضير مدخلات النموذج (تحويل الصورة إلى Float32List مع التطبيع)
  // هذه الدالة ثابتة (static) لأنها لا تحتاج الوصول إلى حالة الكائن، فقط تتعامل مع المدخل (الصورة)
  static Float32List _prepareInputTensor(img.Image image) {
    final int W = image.width;
    final int H = image.height;
    var buffer = Float32List(W * H * 3); // نحتاج 3 قنوات RGB للمدخلات
    int pixelIndex = 0; // فهرس البايت الحالي في المخزن الناتج
    Uint8List bytes = image.getBytes(); // الحصول على بيانات البكسل الخام كـ bytes (عادة RGB أو RGBA)
    int bytesPerPixel = image.numChannels; // عدد قنوات الصورة (المفترض 3 أو 4)

    // التحقق من أن الصورة لديها على الأقل 3 قنوات لإنشاء مدخل RGB
    if (bytesPerPixel < 3) {
      dev.log("Error: Image has less than 3 channels (${bytesPerPixel}), cannot prepare RGB input tensor.");
      throw Exception("Image must have at least 3 channels for model input.");
    }

    // التحقق من أن عدد البايتات كافٍ للحجم المعلن للصورة
    if (bytes.length < W * H * bytesPerPixel) {
      dev.log("Error: Image byte data length mismatch. Expected at least ${W * H * bytesPerPixel}, got ${bytes.length} for ${W}x${H} image with ${bytesPerPixel} bytes per pixel.");
      throw Exception("Image byte data length mismatch.");
    }

    // حلقة على جميع بايتات البكسل في الصورة الأصلية (التي تم تحجيمها بالفعل لمدخل النموذج)
    for (int i = 0; i < bytes.length; i += bytesPerPixel) {
      // قراءة قيم RGB (أول 3 بايتات للبكسل)
      int r = bytes[i];
      int g = bytes[i + 1];
      int b = bytes[i + 2];

      // تطبيق التطبيع (Normalization) بقسمة قيم البكسل على 255.0
      buffer[pixelIndex++] = r / AppConstants.normalizationFactor;
      buffer[pixelIndex++] = g / AppConstants.normalizationFactor;
      buffer[pixelIndex++] = b / AppConstants.normalizationFactor;
      // إذا كانت الصورة الأصلية RGBA (bytesPerPixel == 4)، يتم تجاهل البايت الرابع (قناة ألفا) هنا
    }

    return buffer; // إرجاع المخزن Float32List الجاهز كمدخل للنموذج
  }
}