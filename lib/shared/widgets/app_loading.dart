import 'package:flutter/material.dart';

import '../constants/app_ui_constants.dart';

/// Indicatore di caricamento condiviso.
class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: AppUiConstants.spacingMedium),
            Text(message!),
          ],
        ],
      ),
    );
  }
}
