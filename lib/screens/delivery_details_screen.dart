import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import 'gps_tracking_screen.dart';

const _brandOrange = Color(0xFFF97316);
const _successGreen = Color(0xFF4ADE80);
const _warning = Color(0xFFFFB020);
const _appBg = Color(0xFF151515);
const _surface = Color(0xFF222222);
const _border = Color(0xFF343434);
const _textMuted = Color(0xFFB8B8B8);

class DeliveryDetailsScreen extends StatefulWidget {
  const DeliveryDetailsScreen({super.key});

  static const String routeName = '/delivery_details';

  @override
  State<DeliveryDetailsScreen> createState() => _DeliveryDetailsScreenState();
}

class _DeliveryDetailsScreenState extends State<DeliveryDetailsScreen> {
  final _supabaseService = SupabaseService();

  Map<String, dynamic>? _delivery;
  bool _didLoadArguments = false;
  bool _isRefreshing = false;
  bool _isUpdatingStatus = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadArguments) return;
    _didLoadArguments = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _delivery = Map<String, dynamic>.from(args);
      _refreshDelivery();
    }
  }

  Future<void> _refreshDelivery() async {
    final id = _textValue(_delivery, const ['id']);
    if (id == null) return;

    setState(() => _isRefreshing = true);
    try {
      final latest = await _supabaseService.getDeliveryById(id);
      if (!mounted) return;
      if (latest != null) {
        setState(() => _delivery = latest);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not refresh delivery: $error')),
      );
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _updateStatus(String status) async {
    final id = _textValue(_delivery, const ['id']);
    if (id == null || _isUpdatingStatus) return;

    setState(() => _isUpdatingStatus = true);
    try {
      await _supabaseService.updateDeliveryStatus(id, status);
      if (!mounted) return;
      setState(() {
        _delivery = {...?_delivery, 'status': status};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delivery marked ${_formatStatus(status)}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update status: $error')),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  void _openTracking() {
    Navigator.pushNamed(context, GpsTrackingScreen.routeName);
  }

  @override
  Widget build(BuildContext context) {
    final delivery = _delivery;

    return Scaffold(
      backgroundColor: _appBg,
      appBar: AppBar(
        backgroundColor: _appBg,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Delivery Details',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _isRefreshing ? null : _refreshDelivery,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _brandOrange,
                    ),
                  )
                : const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh delivery',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: delivery == null
            ? const _MissingDelivery()
            : RefreshIndicator(
                onRefresh: _refreshDelivery,
                color: _brandOrange,
                backgroundColor: _surface,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    _SummaryPanel(delivery: delivery),
                    const SizedBox(height: 14),
                    _SectionPanel(
                      title: 'Route',
                      icon: Icons.route_outlined,
                      children: [
                        _DetailLine(
                          icon: Icons.inventory_2_outlined,
                          label: 'Pickup',
                          value: _textValue(delivery, const [
                            'pickup_address',
                            'pickLocation',
                            'pick_location',
                            'sender_address',
                          ]),
                        ),
                        _DetailLine(
                          icon: Icons.location_on_outlined,
                          label: 'Dropoff',
                          value: _textValue(delivery, const [
                            'delivery_address',
                            'dropLocation',
                            'drop_location',
                            'dropoff_address',
                          ]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SectionPanel(
                      title: 'Recipient',
                      icon: Icons.person_outline,
                      children: [
                        _DetailLine(
                          icon: Icons.badge_outlined,
                          label: 'Name',
                          value: _textValue(delivery, const [
                            'recipient_name',
                            'receiver_name',
                            'customer_name',
                          ]),
                        ),
                        _DetailLine(
                          icon: Icons.call_outlined,
                          label: 'Phone',
                          value: _textValue(delivery, const [
                            'recipient_phone',
                            'receiver_phone',
                            'customer_phone',
                          ]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SectionPanel(
                      title: 'Parcel',
                      icon: Icons.inventory_2_outlined,
                      children: [
                        _DetailLine(
                          icon: Icons.description_outlined,
                          label: 'Package',
                          value: _textValue(delivery, const [
                            'package_description',
                            'description',
                            'parcel_description',
                          ]),
                        ),
                        _DetailLine(
                          icon: Icons.straighten_outlined,
                          label: 'Distance',
                          value: _distanceValue(delivery),
                        ),
                        _DetailLine(
                          icon: Icons.payments_outlined,
                          label: 'Price',
                          value: _priceValue(delivery),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SectionPanel(
                      title: 'Timeline',
                      icon: Icons.schedule_outlined,
                      children: [
                        _DetailLine(
                          icon: Icons.add_circle_outline,
                          label: 'Created',
                          value: _dateValue(delivery, const [
                            'created_at',
                            'createdAt',
                            'created_at_iso',
                          ]),
                        ),
                        _DetailLine(
                          icon: Icons.update_outlined,
                          label: 'Updated',
                          value: _dateValue(delivery, const [
                            'updated_at',
                            'updatedAt',
                          ]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _StatusActions(
                      currentStatus: _textValue(delivery, const ['status']),
                      isUpdating: _isUpdatingStatus,
                      onStatusSelected: _updateStatus,
                      onOpenTracking: _openTracking,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  final Map<String, dynamic> delivery;

  const _SummaryPanel({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final code =
        _textValue(delivery, const ['tracking_code', 'parcel_id', 'id']) ??
        'N/A';
    final status = _textValue(delivery, const ['status']) ?? 'unknown';

    return _SurfacePanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _brandOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.local_shipping_outlined,
              color: _brandOrange,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _shortCode(code),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StatusPill(status: status),
        ],
      ),
    );
  }
}

class _StatusActions extends StatelessWidget {
  final String? currentStatus;
  final bool isUpdating;
  final ValueChanged<String> onStatusSelected;
  final VoidCallback onOpenTracking;

  const _StatusActions({
    required this.currentStatus,
    required this.isUpdating,
    required this.onStatusSelected,
    required this.onOpenTracking,
  });

  @override
  Widget build(BuildContext context) {
    final status = currentStatus ?? 'pending';
    const actions = [
      MapEntry('accepted', 'Accept'),
      MapEntry('picked_up', 'Picked up'),
      MapEntry('in_transit', 'In transit'),
      MapEntry('completed', 'Complete'),
    ];

    return _SurfacePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.task_alt_outlined,
                color: _brandOrange,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Actions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isUpdating)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _brandOrange,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onOpenTracking,
            icon: const Icon(Icons.gps_fixed_outlined, size: 18),
            label: const Text('Open GPS Tracking'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actions.map((action) {
              final selected = action.key == status;
              return OutlinedButton(
                onPressed: isUpdating || selected
                    ? null
                    : () => onStatusSelected(action.key),
                child: Text(
                  selected ? _formatStatus(action.key) : action.value,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionPanel({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: _brandOrange, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _textMuted, size: 18),
          const SizedBox(width: 10),
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                color: _textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value == null || value!.trim().isEmpty ? 'Not set' : value!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == 'completed'
        ? _successGreen
        : status == 'pending'
        ? _warning
        : _brandOrange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        _formatStatus(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SurfacePanel({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      padding: padding,
      child: child,
    );
  }
}

class _MissingDelivery extends StatelessWidget {
  const _MissingDelivery();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Delivery details are not available.',
        style: TextStyle(color: _textMuted),
      ),
    );
  }
}

String? _textValue(Map<String, dynamic>? data, List<String> keys) {
  if (data == null) return null;
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

String? _distanceValue(Map<String, dynamic> delivery) {
  final value = _textValue(delivery, const ['distance', 'distance_km']);
  if (value == null) return null;
  final number = num.tryParse(value);
  if (number == null) return '$value km';
  return '${number.toStringAsFixed(number % 1 == 0 ? 0 : 1)} km';
}

String? _priceValue(Map<String, dynamic> delivery) {
  final value = _textValue(delivery, const ['price', 'amount', 'delivery_fee']);
  if (value == null) return null;
  final number = num.tryParse(value);
  if (number == null) return value;
  return 'LKR ${number.toStringAsFixed(2)}';
}

String? _dateValue(Map<String, dynamic> delivery, List<String> keys) {
  final value = _textValue(delivery, keys);
  if (value == null) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final local = parsed.toLocal();
  final date =
      '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

String _shortCode(String code) {
  if (code.length <= 12) return code;
  return code.substring(0, 12);
}

String _formatStatus(String status) {
  final text = status.replaceAll('_', ' ').trim();
  if (text.isEmpty) return 'Unknown';
  return text[0].toUpperCase() + text.substring(1);
}
