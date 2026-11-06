import 'package:flutter/material.dart';
import 'money_identifier_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Money Identifier AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const MoneyIdentifierApp(),
    );
  }
}