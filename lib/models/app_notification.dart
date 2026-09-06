import 'package:flutter/material.dart';

/// One row of `public.notifications`: the in-app copy of a push, kept so a
/// swiped-away notification is not lost.
class AppNotification {
  final String id;
  final String title;
  final String body;

  /// Event that produced it: `trip_assigned`, `delivery_added`,
  /// `delivery_cancelled`, `delivery_reassigned`, or anything the server adds
  /// later. Unknown values fall back to a neutral icon.
  final String type;

  final String? deliveryId;
  final String? tripId;
  final DateTime? createdAt;
  final DateTime? readAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.deliveryId,
    this.tripId,
    this.createdAt,
    this.readAt,
  });

  bool get isUnread => readAt == null;

  IconData get icon {
    switch (type) {
      case 'trip_assigned':
        return Icons.assignment_turned_in_outlined;
      case 'delivery_added':
        return Icons.add_box_outlined;
      case 'delivery_cancelled':
        return Icons.cancel_outlined;
      case 'delivery_reassigned':
        return Icons.swap_horiz_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color get color {
    switch (type) {
      case 'trip_assigned':
        return const Color(0xFF4ADE80);
      case 'delivery_added':
        return const Color(0xFF60A5FA);
      case 'delivery_cancelled':
        return const Color(0xFFF87171);
      case 'delivery_reassigned':
        return const Color(0xFFFFB020);
      default:
        return const Color(0xFFF97316);
    }
  }

  static AppNotification fromRow(Map<String, dynamic> row) {
    return AppNotification(
      id: row['id']?.toString() ?? '',
      title: row['title']?.toString() ?? 'Notification',
      body: row['body']?.toString() ?? '',
      type: row['type']?.toString() ?? 'general',
      deliveryId: _text(row['delivery_id']),
      tripId: _text(row['trip_id']),
      createdAt: _date(row['created_at']),
      readAt: _date(row['read_at']),
    );
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static DateTime? _date(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  /// Compact age for the list: "just now", "12m", "3h", "5d", then a date.
  String get relativeTime {
    final created = createdAt;
    if (created == null) return '';

    final diff = DateTime.now().difference(created);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';

    final month = created.month.toString().padLeft(2, '0');
    final day = created.day.toString().padLeft(2, '0');
    return '$day/$month';
  }
}
