import 'package:flutter/material.dart';
import '../models/order.dart';
import '../../core/constants/app_colors.dart';

/// Vertical stepper for the customer order-tracking screen.
class StatusStepper extends StatelessWidget {
  final OrderStatus current;
  const StatusStepper({super.key, required this.current});

  static const _flow = [
    OrderStatus.placed,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.picked_up,
    OrderStatus.on_the_way,
    OrderStatus.delivered,
  ];

  @override
  Widget build(BuildContext context) {
    if (current == OrderStatus.cancelled) {
      return const ListTile(
        leading: Icon(Icons.cancel, color: AppColors.danger),
        title: Text('Order cancelled'),
      );
    }
    final currentIndex = _flow.indexOf(current);
    return Column(
      children: List.generate(_flow.length, (i) {
        final done = i <= currentIndex;
        final isLast = i == _flow.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: done ? AppColors.secondary : AppColors.divider,
                    child: Icon(done ? Icons.check : Icons.circle,
                        size: 12, color: Colors.white),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: done ? AppColors.secondary : AppColors.divider,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 2),
                child: Text(_flow[i].label,
                    style: TextStyle(
                      fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                      color: done ? AppColors.textDark : AppColors.textMuted,
                    )),
              ),
            ],
          ),
        );
      }),
    );
  }
}
