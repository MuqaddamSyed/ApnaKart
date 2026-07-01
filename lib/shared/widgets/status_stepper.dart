import 'package:flutter/material.dart';
import '../models/order.dart';
import '../../core/constants/app_colors.dart';

/// Vertical stepper for the customer order-tracking screen.
class StatusStepper extends StatelessWidget {
  final OrderStatus current;
  const StatusStepper({super.key, required this.current});

  // Simplified customer flow.
  static const _flow = [
    OrderStatus.placed,
    OrderStatus.confirmed,
    OrderStatus.on_the_way,
    OrderStatus.arrived,
    OrderStatus.delivered,
  ];

  static const _labels = {
    OrderStatus.placed: 'Order placed',
    OrderStatus.confirmed: 'Accepted · delivery partner assigned',
    OrderStatus.on_the_way: 'Picked up · on the way',
    OrderStatus.arrived: 'Delivery partner reached you',
    OrderStatus.delivered: 'Delivered',
  };

  /// Maps any (incl. legacy) status onto the flow index.
  int _indexFor(OrderStatus s) {
    switch (s) {
      case OrderStatus.placed:
        return 0;
      case OrderStatus.confirmed:
      case OrderStatus.preparing:
        return 1;
      case OrderStatus.picked_up:
      case OrderStatus.on_the_way:
        return 2;
      case OrderStatus.arrived:
        return 3;
      case OrderStatus.delivered:
        return 4;
      case OrderStatus.returned:
      case OrderStatus.cancelled:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (current == OrderStatus.cancelled) {
      return const ListTile(
        leading: Icon(Icons.cancel, color: AppColors.danger),
        title: Text('Order cancelled'),
      );
    }
    if (current == OrderStatus.returned) {
      return const ListTile(
        leading: Icon(Icons.assignment_return, color: AppColors.danger),
        title: Text('Order returned'),
        subtitle: Text('This order was not accepted at delivery.'),
      );
    }
    final currentIndex = _indexFor(current);
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
                child: Text(_labels[_flow[i]]!,
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
