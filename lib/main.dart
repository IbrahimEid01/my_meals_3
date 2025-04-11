// lib/main.dart
import 'dart:convert';
import 'dart:developer'; // لاستخدام log
import 'package:flutter/material.dart';
import 'package:my_meals_3/screens/home_screen.dart'; // تأكد من المسار
import 'package:my_meals_3/screens/user_data.dart'; // تأكد من المسار (الكلاس UserData)
import 'package:my_meals_3/screens/user_info_screen.dart'; // تأكد من المسار
import 'package:my_meals_3/utils/ImagePreprocessing.dart'; // تم الإبقاء عليه للتحميل المسبق
import 'package:shared_preferences/shared_preferences.dart';

// تأكد من وجود تعريف UserData هنا أو استيراده بشكل صحيح
// class UserData { ... fromJson ... }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  log("App starting...");

  // قراءة بيانات المستخدم
  final prefs = await SharedPreferences.getInstance();
  final userDataJson = prefs.getString('userData');
  Widget initialScreen = const UserInfoScreen(); // الافتراضي هو شاشة إدخال المعلومات

  if (userDataJson != null) {
    log("User data found in SharedPreferences.");
    try {
      final userDataMap = jsonDecode(userDataJson);
      // هنا نفترض أن UserData.fromJson موجودة في ملف user_data.dart
      final userData = UserData.fromJson(userDataMap);

      // التحقق من اكتمال بيانات المستخدم الأساسية للانتقال للشاشة الرئيسية
      if (userData.userName != null && userData.userName!.isNotEmpty &&
          userData.userAge != null &&
          userData.userHeight != null &&
          userData.userWeight != null &&
          userData.userCondition != null // نفترض أن هذا حقل هام أيضاً
      ) {
        log("User data seems complete. Setting initial screen to MainScreen.");
        initialScreen = const MainScreen();
      } else {
        log("User data incomplete. Setting initial screen to UserInfoScreen.");
      }
    } catch(e) {
      log("Error decoding user data: $e. Setting initial screen to UserInfoScreen.");
      // إذا حدث خطأ في فك التشفير، نعود لشاشة إدخال المعلومات
      initialScreen = const UserInfoScreen();
    }
  } else {
    log("No user data found. Setting initial screen to UserInfoScreen.");
  }

  // تحميل نموذج التقسيم مسبقاً (يبقى كما هو للاستخدام المستقبلي)
  // لا يسبب ضرراً تحميله حتى لو لم يُستخدم مباشرة في التدفق الحالي
  try {
    log("Attempting to load DeepLabV3 model...");
    await ImagePreprocessing.loadDeepLabModel();
    // لا يوجد log نجاح في الدالة الأصلية, يمكن إضافته هناك
  } catch (e) {
    log("Warning: Failed to pre-load DeepLabV3 model: $e. App will continue.");
    // التطبيق سيستمر حتى لو فشل تحميل هذا النموذج لأنه غير مستخدم حالياً
  }

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  const MyApp({Key? key, required this.initialScreen}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    log("Building MyApp widget...");
    return MaterialApp(
      title: 'My Meals 3',
      theme: ThemeData(
        primarySwatch: Colors.teal, // استخدام الـ primarySwatch أفضل
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: initialScreen,
      debugShowCheckedModeBanner: false, // لإخفاء شعار Debug
    );
  }
}