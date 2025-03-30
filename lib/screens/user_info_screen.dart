import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'user_data.dart';
import 'dart:convert';

class UserInfoScreen extends StatefulWidget {
  const UserInfoScreen({Key? key}) : super(key: key);

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  String? _selectedCondition;
  int _currentStep = 0;

  // حفظ بيانات المستخدم محليًا
  Future<void> _saveUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = UserData(
      userName: _nameController.text,
      userAge: int.parse(_ageController.text),
      userHeight: double.parse(_heightController.text),
      userWeight: double.parse(_weightController.text),
      userCondition: _selectedCondition,
    );
    //تحويل بيانات المستخدم الي JSON
    final userDataJson = jsonEncode(userData.toJson());
    //حفظ البيانات في الـ sharedPreferences
    await prefs.setString('userData', userDataJson);
  }

  // الانتقال إلى الشاشة الرئيسية
  void _navigateToMainScreen() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MainScreen()),
    );
  }

  void _showNextPage() {
    if (_formKey.currentState!.validate()) {
      if (_nameController.text.isEmpty || _ageController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرجاء إدخال جميع الحقول.')),
        );
        return;
      }
      if (_heightController.text.isEmpty || _weightController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرجاء إدخال جميع الحقول.')),
        );
        return;
      }
      if (_selectedCondition == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرجاء تحديد حالة صحية.')),
        );
        return;
      }
      _saveUserData();
      _navigateToMainScreen();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('معلومات المستخدم'),
        ),
        body: Form(
            key: _formKey,
            child: Stepper(
              type: StepperType.horizontal,
              currentStep: _currentStep,
              onStepContinue: () {
                if (_currentStep < 2) {
                  setState(() {
                    _currentStep++;
                  });
                } else {
                  _showNextPage();
                }
              },
              onStepCancel: () {
                if (_currentStep > 0) {
                  setState(() {
                    _currentStep--;
                  });
                }
              },
              steps: <Step>[
                Step(
                  title: const Text('الاسم والعمر'),
                  content: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'الاسم'),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'الرجاء إدخال الاسم';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: _ageController,
                        decoration: const InputDecoration(labelText: 'العمر'),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'الرجاء إدخال العمر';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                Step(
                  title: const Text('الطول والوزن'),
                  content: Column(
                    children: [
                      TextFormField(
                        controller: _heightController,
                        decoration:
                        const InputDecoration(labelText: 'الطول (سم)'),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'الرجاء إدخال الطول';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: _weightController,
                        decoration:
                        const InputDecoration(labelText: 'الوزن (كجم)'),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'الرجاء إدخال الوزن';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                Step(
                  title: const Text('الحالة الصحية'),
                  content: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedCondition,
                        onChanged: (newValue) {
                          setState(() {
                            _selectedCondition = newValue;
                          });
                        },
                        items: <String>[
                          'عادي',
                          'سمنة',
                          'سكري',
                          'كوليسترول',
                        ].map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        decoration:
                        const InputDecoration(labelText: 'الحالة الصحية'),
                        validator: (value) {
                          if (value == null) {
                            return 'الرجاء اختيار الحالة الصحية';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ],
            )
        )
    );
  }
}