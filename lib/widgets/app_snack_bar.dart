import 'package:flutter/material.dart';

enum AppSnackBarType { success, error }

class AppSnackBar {
  const AppSnackBar._();

  static void showSuccess(BuildContext context, String message) {
    _show(
      context,
      title: 'Thành công',
      message: message,
      type: AppSnackBarType.success,
    );
  }

  static void showError(BuildContext context, String message) {
    _show(
      context,
      title: 'Không thành công',
      message: message,
      type: AppSnackBarType.error,
    );
  }

  static void _show(
    BuildContext context, {
    required String title,
    required String message,
    required AppSnackBarType type,
  }) {
    final isSuccess = type == AppSnackBarType.success;
    final backgroundColor = isSuccess
        ? const Color(0xFF047857)
        : const Color(0xFFB91C1C);
    final icon = isSuccess ? Icons.check_circle : Icons.error_outline;

    final snackBar = SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: backgroundColor,
      elevation: 6,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }
}
