import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _language = 'ar';
  String _dataSource = 'local'; // 'local' لقاعدة البيانات المحلية أو 'api' للخدمة الخارجية

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _language = prefs.getString(AppConstants.prefLanguageKey) ?? 'ar';
      _dataSource = prefs.getString(AppConstants.prefDataSourceKey) ?? 'local';
    });
  }




  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefLanguageKey, _language);
    await prefs.setString(AppConstants.prefDataSourceKey, _dataSource);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ الإعدادات')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('الإعدادات'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اختر اللغة:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            DropdownButton<String>(
              value: _language,
              items: [
                DropdownMenuItem(child: Text('العربية'), value: 'ar'),
                DropdownMenuItem(child: Text('English'), value: 'en'),
              ],
              onChanged: (value) {
                setState(() {
                  _language = value!;
                });
              },
            ),
            SizedBox(height: 20),
            Text(
              'مصدر البيانات:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            DropdownButton<String>(
              value: _dataSource,
              items: [
                DropdownMenuItem(child: Text('قاعدة بيانات محلية'), value: 'local'),
                DropdownMenuItem(child: Text('خدمة API'), value: 'api'),
              ],
              onChanged: (value) {
                setState(() {
                  _dataSource = value!;
                });
              },
            ),
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: _saveSettings,
              child: Text('حفظ الإعدادات'),
            ),
          ],
        ),
      ),
    );
  }
}
