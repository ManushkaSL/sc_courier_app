import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../services/supabase_service.dart';
import 'delivery_details_screen.dart';

const _brandOrange = Color(0xFFF97316);
const _appBg = Color(0xFF151515);
const _surface = Color(0xFF222222);
const _border = Color(0xFF343434);
const _textMuted = Color(0xFFB8B8B8);

/// In-app copy of everything that was pushed to this rider, so a notification
/// swiped away on the lock screen is not lost.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  static const String routeName = '/notifications';

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _supabaseService = SupabaseService();

  List<AppNotification> _notifications = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final notifications = await _supabaseService.getNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _supabaseService.markAllNotificationsRead();
      if (!mounted) return;
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not mark all as read: $e')),
      );
    }
  }

  Future<void> _open(AppNotification notification) async {
    if (notification.isUnread) {
      // Optimistic: the row un-bolds immediately, and a failed write only means
      // it still looks unread next time.
      setState(() {
        _notifications = [
          for (final item in _notifications)
            if (item.id == notification.id)
              AppNotification(
                id: item.id,
                title: item.title,
                body: item.body,
                type: item.type,
                deliveryId: item.deliveryId,
                tripId: item.tripId,
                createdAt: item.createdAt,
                readAt: DateTime.now(),
              )
            else
              item,
        ];
      });
      // Failure here only means it still looks unread next time.
      unawaited(_supabaseService.markNotificationRead(notification.id));
    }

    final deliveryId = notification.deliveryId;
    if (deliveryId == null || !mounted) return;

    await Navigator.pushNamed(
      context,
      DeliveryDetailsScreen.routeName,
      arguments: {'id': deliveryId},
    );
  }

  int get _unreadCount => _notifications.where((n) => n.isUnread).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _appBg,
      appBar: AppBar(
        backgroundColor: _appBg,
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: _brandOrange,
          backgroundColor: _surface,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _brandOrange),
      );
    }

    if (_error != null) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Could not load notifications',
        message: _error!,
        onRetry: _load,
      );
    }

    if (_notifications.isEmpty) {
      return const _MessageState(
        icon: Icons.notifications_none,
        title: 'Nothing yet',
        message:
            'New assignments and changes to your deliveries will show up here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _notifications.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final notification = _notifications[index];
        return _NotificationTile(
          notification: notification,
          onTap: () => _open(notification),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = notification.isUnread;

    return Material(
      color: unread ? notification.color.withValues(alpha: 0.07) : _surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: unread
                  ? notification.color.withValues(alpha: 0.35)
                  : _border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: notification.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  notification.icon,
                  color: notification.color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          notification.relativeTime,
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: notification.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: const TextStyle(
                          color: _textMuted,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (notification.deliveryId != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: _textMuted, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // Wrapped in a scroll view so pull-to-refresh still works when empty.
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 90, 28, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Icon(icon, color: _textMuted, size: 46),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _textMuted, fontSize: 13, height: 1.4),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 18),
          Center(
            child: OutlinedButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ),
        ],
      ],
    );
  }
}
