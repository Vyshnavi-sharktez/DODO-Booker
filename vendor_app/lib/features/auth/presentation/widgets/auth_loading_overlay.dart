import 'package:flutter/material.dart';

class AuthLoadingOverlay extends StatelessWidget {
  const AuthLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
  });

  final bool isLoading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: AbsorbPointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.25),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
