import 'package:flutter/material.dart';

/// Work state a rider sets for themselves.
///
/// The [key] values are what the `rider.availability` column stores, so the
/// admin side can filter new deliveries down to riders sitting on
/// [RiderAvailability.available].
enum RiderAvailability {
  available(
    key: 'available',
    label: 'Available',
    description: 'Ready to receive new deliveries',
    icon: Icons.check_circle_outline,
    color: Color(0xFF4ADE80),
  ),
  onDelivery(
    key: 'on_delivery',
    label: 'On delivery',
    description: 'Working on a delivery right now',
    icon: Icons.local_shipping_outlined,
    color: Color(0xFFF97316),
  ),
  offline(
    key: 'offline',
    label: 'Offline',
    description: 'Not working, do not assign deliveries',
    icon: Icons.do_not_disturb_on_outlined,
    color: Color(0xFF9AA0A6),
  );

  const RiderAvailability({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  /// Value stored in `rider.availability`.
  final String key;

  /// Short name shown in the status pill.
  final String label;

  /// One-line explanation shown under the rider name and in the picker.
  final String description;

  final IconData icon;
  final Color color;

  /// Only riders in this state should be handed new work.
  bool get acceptsNewDeliveries => this == RiderAvailability.available;

  /// Parses a stored value. Unknown, missing, or legacy values fall back to
  /// [RiderAvailability.offline] so a rider is never silently treated as
  /// assignable.
  static RiderAvailability fromKey(Object? value) {
    if (value is bool) return value ? available : offline;

    final raw = value?.toString().trim().toLowerCase().replaceAll(
      RegExp(r'[\s-]+'),
      '_',
    );
    if (raw == null || raw.isEmpty) return offline;

    for (final option in RiderAvailability.values) {
      if (option.key == raw) return option;
    }

    // Tolerate the wording the app used before availability was a column.
    switch (raw) {
      case 'online':
      case 'active':
      case 'ready':
        return available;
      case 'on_ride':
      case 'on_trip':
      case 'busy':
      case 'delivering':
        return onDelivery;
      case 'off':
      case 'inactive':
      case 'unavailable':
        return offline;
    }

    return offline;
  }
}
