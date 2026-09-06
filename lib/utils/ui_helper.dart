import 'package:flutter/material.dart';

void showStyledSnackBar(BuildContext context, String message, {bool isError = false, Duration duration = const Duration(seconds: 1)}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message, style: const TextStyle(color: Colors.white)),
    backgroundColor: (isError ? Colors.redAccent : Colors.blue).withOpacity(0.9),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12.0),
    ),
    margin: const EdgeInsets.all(16),
    duration: duration,
  ));
}
