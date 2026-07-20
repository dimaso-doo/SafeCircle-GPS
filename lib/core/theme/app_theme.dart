import 'package:flutter/material.dart';

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF0B6E4F),
    brightness: Brightness.light,
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  ),
);
