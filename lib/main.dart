import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:my_meals_3/screens/home_screen.dart';
import 'package:my_meals_3/screens/user_data.dart';
import 'package:my_meals_3/screens/user_info_screen.dart';
import 'package:my_meals_3/utils/ImagePreprocessing.dart'; // تأكد من استخدام الحروف الصغيرة
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // قراءة بيانات المستخدم من SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final userDataJson = prefs.getString('userData');

  // تحديد الشاشة الأولية بناءً على بيانات المستخدم
  Widget initialScreen = const UserInfoScreen();
  if (userDataJson != null) {
    final userData = UserData.fromJson(jsonDecode(userDataJson));
    if (userData.userName != null &&
        userData.userAge != null &&
        userData.userHeight != null &&
        userData.userWeight != null &&
        userData.userCondition != null) {
      initialScreen = const MainScreen();
    }
  }

  // تحميل نموذج DeepLabV3 من وحدة image_preprocessing.dart
  await ImagePreprocessing.loadDeepLabModel();

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  const MyApp({Key? key, required this.initialScreen}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تطبيق التعرف على الأطعمة المصرية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: initialScreen,
    );
  }
}
