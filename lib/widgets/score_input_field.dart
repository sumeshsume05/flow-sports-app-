import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ScoreInputField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const ScoreInputField({super.key, required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall,
      decoration: InputDecoration(
        labelText: label,
      ),
    );
  }
}
