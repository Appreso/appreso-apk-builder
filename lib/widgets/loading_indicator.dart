import 'package:flutter/material.dart';

class AppResoLoader extends StatelessWidget {
  final Color color;
  final String? text;

  const AppResoLoader({
    super.key,
    this.color = const Color(0xFF6366f1),
    this.text = 'Loading...',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
        if (text != null && text!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            text!,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
