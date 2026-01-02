import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';

class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38, // Standard macOS title bar height approx
      color: Colors.transparent,
      child: WindowTitleBarBox(
        child: Row(
          children: [
            // Standard macOS window buttons are typically on the left, handled by the OS.
            // We just provide the drag handle.
            const SizedBox(width: 8),

            // Custom window buttons removed to avoid duplication with native macOS buttons.
            const SizedBox(width: 10),
            Expanded(child: MoveWindow()),
          ],
        ),
      ),
    );
  }
}
