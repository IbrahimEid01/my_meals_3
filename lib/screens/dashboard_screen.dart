import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // حاوية 1
            Container(
              width: 200,
              height: 100,
              color: Colors.blue,
              margin: const EdgeInsets.all(10),
              child: const Center(child: Text('حاوية 1')),
            ),
            // حاوية 2
            Container(
              width: 200,
              height: 100,
              color: Colors.green,
              margin: const EdgeInsets.all(10),
              child: const Center(child: Text('حاوية 2')),
            ),
            // حاوية 3
            Container(
              width: 200,
              height: 100,
              color: Colors.red,
              margin: const EdgeInsets.all(10),
              child: const Center(child: Text('حاوية 3')),
            ),
          ],
        ),
      ),
    );
  }
}