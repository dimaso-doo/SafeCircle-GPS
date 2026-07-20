import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isSecondary = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isSecondary;

  @override
  Widget build(BuildContext context) {
    final button = isSecondary
        ? OutlinedButton(onPressed: isLoading ? null : onPressed, child: _label())
        : ElevatedButton(onPressed: isLoading ? null : onPressed, child: _label());

    return SizedBox(
      width: double.infinity,
      child: Theme(data: Theme.of(context).copyWith(textButtonTheme: const TextButtonThemeData()), child: button),
    );
  }

  Widget _label() {
    return isLoading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);
  }
}
