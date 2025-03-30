import 'package:flutter/material.dart';
import 'package:my_meals_3/screens/recipes_screen.dart';
import 'camera_screen.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'my_calories_screen.dart';
import 'user_type_page.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0; // تبدأ بـ CameraScreen

  void _selectPage(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  final List<Widget> _pages = [
    const DashboardScreen(), // 0
    const RecipesScreen(), // 1
    const MyCaloriesScreen(), // 2
    const HistoryScreen(), // 3
    const SettingsScreen(), // 4

  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("التعرف على الأطعمة المصرية"),
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            const UserAccountsDrawerHeader(
              accountName: Text("اسم المستخدم"),
              accountEmail: Text("user@example.com"),
              currentAccountPicture: CircleAvatar(
                child: Icon(Icons.person),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text("إضافة مستخدم جديد"),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text("الإعدادات"),
              onTap: () {
                _selectPage(4);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      floatingActionButton: _currentIndex == 2
     ?FloatingActionButton(
        onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const CustomCameraScreen(),),);
        },
        child: const Icon(Icons.camera_alt),
      )
      : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedIndex: _currentIndex,
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu),
            label: 'الوصفات',
          ),
    NavigationDestination(
    icon: Icon(Icons.local_fire_department),
      label: 'سعراتي',
    ),
          NavigationDestination(
            icon: Icon(Icons.history),
            label: 'السجل',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}