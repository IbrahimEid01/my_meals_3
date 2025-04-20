import 'dart:developer' as dev; // إعطاء اسم مستعار لـ log من dart:developer
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/NutritionModelInput.dart'; // تأكد من أن هذا المسار صحيح
import '../models/NutritionModelOutput.dart'; // تأكد من أن هذا المسار صحيح
import '../utils/constants.dart'; // تأكد من أن هذا المسار صحيح
import 'dart:math' hide log; // إخفاء log من dart:math لتجنب التعارض

class DishNutritionRegression {
  Interpreter? _interpreter; // متغير الـ interpreter الخاص بكل كائن من الفئة (غير static)

  DishNutritionRegression() {
    _loadModel();
  }

  Future<void> _loadModel() async {
    // إضافة تحقق للتأكد من أن المترجم لم يتم تحميله بالفعل (مع التحقق من العنوان للتأكد من أنه صالح)
    if (_interpreter != null && _interpreter!.address != 0) {
      dev.log('Nutrition model already loaded.');
      return;
    }
    try {
      final interpreterOptions = InterpreterOptions();
      // يمكنك إضافة delegates هنا لتحسين الأداء (CPU, GPU, NNAPI)
      // interpreterOptions.addDelegate(GpuDelegateV2()); // مثال لـ GPU

      // تحميل النموذج من الـ assets
      _interpreter = await Interpreter.fromAsset(
        AppConstants.nutritionModelPath,
        options: interpreterOptions,
      );

      // التحقق من أن المترجم تم إنشاؤه بنجاح
      if (_interpreter == null || _interpreter!.address == 0) {
        dev.log('Error loading nutrition model: Interpreter not created.');
        // لا حاجة لاستدعاء _disposeInterpreter هنا لأن المترجم لم يتم إنشاؤه بنجاح
        return; // الخروج إذا فشل الإنشاء
      }

      dev.log('Nutrition model loaded successfully.');
      dev.log('Nutrition Input Tensors: ${_interpreter?.getInputTensors()}');
      dev.log('Nutrition Output Tensors: ${_interpreter?.getOutputTensors()}');

      // تحققات إضافية لشكل المدخل والمخرجات عند التحميل بناءً على تحليل الـ PDF وسجلات التشغيل
      if (_interpreter!.getInputTensors().isEmpty || _interpreter!.getOutputTensors().isEmpty) {
        dev.log('Warning: Nutrition model has no input or output tensors.');
      } else {
        var inputShape = _interpreter!.getInputTensors().first.shape;
        // التحقق من شكل المدخلات: [1, 224, 224, 3]
        if (inputShape.length != 4 || inputShape[0] != 1 || inputShape[1] != AppConstants.nutritionInputSize || inputShape[2] != AppConstants.nutritionInputSize || inputShape[3] != 3) {
          dev.log('Warning: Nutrition model input shape $inputShape does not match expected [1, ${AppConstants.nutritionInputSize}, ${AppConstants.nutritionInputSize}, 3]');
        }
        var outputTensors = _interpreter!.getOutputTensors();
        // التحقق من عدد المخرجات: 5
        if (outputTensors.length != 5) {
          dev.log('Warning: Nutrition model output tensors count ${outputTensors.length} does not match expected 5.');
        } else {
          // التحقق من شكل كل مخرج: [1, 1]
          for(int i=0; i<outputTensors.length; i++) {
            var outputShape = outputTensors[i].shape;
            if (outputShape.length != 2 || outputShape[0] != 1 || outputShape[1] != 1) {
              dev.log('Warning: Nutrition model output tensor $i shape $outputShape does not match expected [1, 1]');
            }
          }
        }
      }


    } catch (e) {
      dev.log('Error loading nutrition model: $e'); // تسجيل أي خطأ يحدث أثناء التحميل
      _disposeInterpreter(); // تأكد من التخلص من المترجم في حالة الفشل
    }
  }

  Future<NutritionModelOutput> predictNutrition(NutritionModelInput input) async {
    // التحقق من أن المترجم جاهز قبل الاستخدام
    if (_interpreter == null || _interpreter!.address == 0) {
      dev.log('Error: Nutrition model not loaded or failed to load.');
      return NutritionModelOutput(calories: 0.0, mass: 0.0, fat: 0.0, carbs: 0.0, protein: 0.0);
    }

    try {
      // تجهيز بيانات الإدخال: تحويل input.imageData إلى Float32List ثم إعادة تشكيلها للشكل المطلوب [1, 224, 224, 3]
      var inputList = Float32List.fromList(input.imageData);
      int expectedInputSize = 1 * AppConstants.nutritionInputSize * AppConstants.nutritionInputSize * 3;

      // التحقق من حجم بيانات المدخلات
      if (inputList.length != expectedInputSize) {
        dev.log('Error: Nutrition input data size mismatch! Expected $expectedInputSize, got ${inputList.length}');
        // لا ترمي استثناء هنا، فقط سجل الخطأ ورجع قيم صفرية لتجنب تعطل التطبيق
        return NutritionModelOutput(calories: 0.0, mass: 0.0, fat: 0.0, carbs: 0.0, protein: 0.0);
      }

      final inputBuffer = inputList.buffer.asFloat32List().reshape(
        [1, AppConstants.nutritionInputSize, AppConstants.nutritionInputSize, 3],
      );

      // --- بداية التعديلات النهائية للتعامل مع مخرجات متعددة بشكل صحيح ---

      final outputTensors = _interpreter!.getOutputTensors();
      // التحقق من أن عدد المخرجات هو 5 كما هو متوقع لنموذج التغذية
      if (outputTensors.length != 5) {
        dev.log('Error: Expected 5 output tensors, but got ${outputTensors.length}. Output Tensors: $outputTensors');
        return NutritionModelOutput(calories: 0.0, mass: 0.0, fat: 0.0, carbs: 0.0, protein: 0.0);
      }

      // تجهيز مخازن للمخرجات في outputMap (كل مخزن على شكل [1, 1])
      final Map<int, Object> outputMap = {};
      for (int i = 0; i < outputTensors.length; i++) {
        final outputShape = outputTensors[i].shape;
        // يجب أن يكون شكل كل مخرج [1, 1] بناءً على تحليل الـ PDF وسجلات التشغيل
        if (outputShape.length != 2 || outputShape[0] != 1 || outputShape[1] != 1) {
          dev.log('Error: Expected shape [1, 1] for output tensor $i, but got $outputShape.');
          // يمكنك إضافة المزيد من التحقق هنا على نوع المخرج إذا لزم الأمر
          return NutritionModelOutput(calories: 0.0, mass: 0.0, fat: 0.0, carbs: 0.0, protein: 0.0);
        }
        // يجب توفير مخزن تم تشكيله صراحةً على شكل [1, 1] لحل مشكلة عدم تطابق الشكل runtime
        outputMap[i] = Float32List(1).reshape([1, 1]); // *** التأكيد على reshape([1, 1]) ***
      }

      dev.log('Running nutrition inference...');

      // طباعة تفاصيل outputMap قبل التشغيل للمساعدة في التشخيص إذا استمرت المشكلة (تم تصحيح أخطاء التجميع هنا)
      dev.log('Nutrition outputMap setup before run: $outputMap');
      outputMap.forEach((key, value) {
        // للوصول إلى length و runtimeType بشكل آمن، نقوم بكاست إلى TypedData
        if (value is TypedData) {
          String shapeInfo = 'Unknown Shape';
          // محاولة تحديد الشكل للـ logging بناءً على بعض الاحتمالات الشائعة بعد التشكيل
          // الوصول إلى طول المخزن بالبايتات أو عدد العناصر عبر buffer
          int lengthInElements = value.buffer.lengthInBytes ~/ value.elementSizeInBytes; // حساب عدد العناصر
          shapeInfo = '[${lengthInElements}]'; // شكل مسطح


          dev.log('  Output Tensor $key: Type=${value.runtimeType}, Length=${lengthInElements}, Shape=$shapeInfo'); // *** تم تصحيح خطأ التجميع: استخدام lengthInElements المحسوب ***
        } else {
          dev.log('  Output Tensor $key: Type=${value.runtimeType}'); // تسجيل نوع القيمة إذا لم تكن TypedData
        }
      });


      // استخدام runForMultipleInputs للموديلات ذات المخرجات المتعددة
      _interpreter!.runForMultipleInputs([inputBuffer], outputMap);
      dev.log('Nutrition inference completed.');

      // استخراج القيم من مخازن المخرجات - استخدام الكاست إلى List<double> والوصول للعنصر الأول
      // بما أن كل مخزن هو Float32List (وهو نوع من List<double>) وتم تشكيله على [1, 1]
      // الوصول (outputMap[i] as List<double>)[0] يعطي العنصر الأول في القائمة المسطحة (القيمة المفردة)
      // هذا الجزء لا يزال صحيحاً للوصول إلى القيمة العددية بعد أن يملأ المترجم المخزن
      double rawCalories = (outputMap[0] as List<double>)[0];
      double rawMass = (outputMap[1] as List<double>)[0];
      double rawFat = (outputMap[2] as List<double>)[0];
      double rawCarbs = (outputMap[3] as List<double>)[0];
      double rawProtein = (outputMap[4] as List<double>)[0];

      // --- نهاية التعديلات النهائية ---

      dev.log('Raw model outputs: Cal=${rawCalories.toStringAsFixed(4)}, Mass=${rawMass.toStringAsFixed(4)}, Fat=${rawFat.toStringAsFixed(4)}, Carbs=${rawCarbs.toStringAsFixed(4)}, Protein=${rawProtein.toStringAsFixed(4)}');

      // عمليات إلغاء التطبيع كما هي (بناءً على AppConstants)
      double unNormCalories = (rawCalories * AppConstants.unNormCaloriesFactor).abs();
      double unNormMass = (rawMass * AppConstants.unNormMassFactor).abs();
      double unNormFat = (rawFat * AppConstants.unNormFatFactor).abs();
      double unNormCarbs = (rawCarbs * AppConstants.unNormCarbsFactor).abs();
      double unNormProtein = (rawProtein * AppConstants.unNormProteinFactor).abs();

      dev.log('Un-normalized outputs: Cal=${unNormCalories.toStringAsFixed(2)}, Mass=${unNormMass.toStringAsFixed(2)}g, Fat=${unNormFat.toStringAsFixed(2)}g, Carbs=${unNormCarbs.toStringAsFixed(2)}g, Protein=${unNormProtein.toStringAsFixed(2)}g');

      // تحقق من أن القيم غير صفرية قبل الإرجاع للإشارة إلى نجاح التحليل
      if (unNormCalories > 0 || unNormMass > 0 || unNormFat > 0 || unNormCarbs > 0 || unNormProtein > 0) {
        return NutritionModelOutput(
          calories: unNormCalories,
          mass: unNormMass,
          fat: unNormFat,
          carbs: unNormCarbs,
          protein: unNormProtein,
        );
      } else {
        dev.log("Warning: Un-normalized nutrition results are all zero or seem invalid. Returning default zero values.");
        // لا ترفع استثناء هنا، فقط أعد قيماً صفرية واعتبر التحليل فشل
        return NutritionModelOutput(calories: 0.0, mass: 0.0, fat: 0.0, carbs: 0.0, protein: 0.0);
      }


    } catch (e) {
      dev.log('Error during nutrition inference: $e'); // تسجيل أي خطأ يحدث أثناء الاستنتاج
      // في حالة حدوث أي خطأ غير متوقع، نرجع قيم صفرية لتجنب تعطل التطبيق
      return NutritionModelOutput(calories: 0.0, mass: 0.0, fat: 0.0, carbs: 0.0, protein: 0.0);
    }
  }

  // دالة مساعدة للتخلص من الـ interpreter (تم إزالة static لحل خطأ النطاق)
  // هذه الدالة يجب أن تكون دالة عادية (instance method) للوصول إلى _interpreter الخاص بالفئة
  void _disposeInterpreter() { // *** تم إزالة static هنا لحل خطأ التجميع المتعلق بنطاق _interpreter ***
    // تحقق من أن المترجم موجود وصالح قبل محاولة إغلاقه
    if (_interpreter != null && _interpreter!.address != 0) {
      _interpreter!.close();
      //dev.log('Nutrition interpreter disposed using close().'); // log هنا قد تسبب مشكلة إذا استدعيت بعد dispose فعلياً
    }
    _interpreter = null; // تعيين لـ null دائماً بعد المحاولة لتجنب استخدام مؤشر غير صالح
    dev.log('Nutrition interpreter disposed.'); // تسجيل الإغلاق
  }

  // دالة close() العامة لاستدعائها من خارج الفئة (تستدعي دالة dispose المساعدة)
  // هذه الدالة غير static لأنها تستدعى على كائن من DishNutritionRegression
  void close() { // *** هذه الدالة غير static بشكل صحيح ***
    _disposeInterpreter(); // استدعاء الدالة المساعدة غير static
  }
}