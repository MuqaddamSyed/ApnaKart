import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Thin banner shown when the device is offline. Pass [online] from a
/// connectivity provider; kept dependency-free here.
class OfflineBanner extends StatelessWidget {
  final bool online;
  const OfflineBanner({super.key, required this.online});

  @override
  Widget build(BuildContext context) {
    if (online) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.danger,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: const Text('No internet connection',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}
