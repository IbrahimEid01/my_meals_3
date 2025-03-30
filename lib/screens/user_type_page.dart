import 'package:flutter/material.dart';

import 'home_screen.dart';

class UserTypePage extends StatefulWidget {
  const UserTypePage({Key? key}) : super(key: key);

  @override
  State<UserTypePage> createState() => _UserTypePageState();
}
   class _UserTypePageState extends State<UserTypePage> {
   String? _selectedType;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
        onPressed:() {
          setState(() {
            _selectedType = " عادي ";

      });
      },
        style: ElevatedButton.styleFrom(
          backgroundColor:
            _selectedType == " عادي " ? Colors.green : null,
        ),
              child: const Text (' مريض عادي '),
            ),
         const SizedBox(height: 20),
    ElevatedButton(
    onPressed:() {
      setState(() {
        _selectedType = " سكري ";
      });
    },
    style: ElevatedButton.styleFrom(
    backgroundColor:
    _selectedType == " سكري " ? Colors.green : null,

    ),
    child: const Text("مريض سكري "),
    ),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: _selectedType != null
              ? () {
            // الانتقال إلى MainScreen
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (context) => const MainScreen()),
            );
          }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedType != null ? Colors.green : null,
          ),
          child: const Text('التالي'),
        ),
        ],
      ),
    ),
    );
  }
   }