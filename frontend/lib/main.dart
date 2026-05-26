import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: FamCareApp(),
    ),
  );
}

class FamCareApp extends StatelessWidget {
  const FamCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamCare Bulk Scheduler',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
