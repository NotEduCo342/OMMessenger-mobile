import 'package:flutter/material.dart';
import '../models/message.dart';

class MessageStatusIndicator extends StatelessWidget {
  final Message message;

  const MessageStatusIndicator({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    final colorScheme = Theme.of(context).colorScheme;

    switch (message.status) {
      case 'pending':
        icon = Icons.schedule;
        color = Colors.grey;
        break;
      case 'sent':
        icon = Icons.check;
        color = Colors.grey;
        break;
      case 'delivered':
        icon = Icons.done_all;
        color = Colors.grey;
        break;
      case 'read':
        icon = Icons.done_all;
        color = colorScheme.primary;
        break;
      case 'failed':
        icon = Icons.error_outline;
        color = Colors.red;
        break;
      default:
        icon = Icons.schedule;
        color = Colors.grey;
    }

    return Icon(
      icon,
      size: 14,
      color: color,
    );
  }
}

class PendingMessageBadge extends StatelessWidget {
  final int count;

  const PendingMessageBadge({
    super.key,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.sync,
            size: 12,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
