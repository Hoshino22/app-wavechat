import 'package:flutter/material.dart';

Color getAvatarColor(String char) {
  if (char.isEmpty) return Colors.grey;

  final Map<String, Color> letterColors = {
    'A': Colors.red, 'B': Colors.green, 'C': Colors.blue, 'D': Colors.orange,
    'E': Colors.purple, 'F': Colors.teal, 'G': Colors.pink, 'H': Colors.amber,
    'I': Colors.indigo, 'J': Colors.cyan, 'K': Colors.brown, 'L': Colors.lime,
    'M': Colors.lightBlue, 'N': Colors.lightGreen, 'O': Colors.deepOrange,
    'P': Colors.blueGrey, 'Q': Colors.deepPurple, 'R': Colors.redAccent,
    'S': Colors.greenAccent, 'T': Colors.orangeAccent, 'U': Colors.purpleAccent,
    'V': Colors.tealAccent, 'W': Colors.yellow, 'X': Colors.black,
    'Y': Colors.grey, 'Z': Colors.blueAccent,
  };
  
  return letterColors[char.toUpperCase()] ?? Colors.grey;
}
