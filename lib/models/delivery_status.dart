import 'package:flutter/material.dart';

/// The stages a delivery moves through, each with its own colour so a rider can
/// tell them apart at a glance instead of reading the badge text.
///
/// The raw `delivery_status` column is free text and has used several spellings
/// over time, so [DeliveryStage.fromStatus] maps them onto these stages while
/// the badge keeps showing whatever word the database actually stores.
enum DeliveryStage {
  /// Handed to the rider, not accepted yet.
  assigned(
    label: 'Assigned',
    color: Color(0xFF60A5FA),
    icon: Icons.assignment_outlined,
  ),

  /// Rider accepted, parcel not collected yet.
  accepted(
    label: 'Accepted',
    color: Color(0xFFFFB020),
    icon: Icons.how_to_reg_outlined,
  ),

  /// Parcel is with the rider.
  pickedUp(
    label: 'Picked up',
    color: Color(0xFFA78BFA),
    icon: Icons.inventory_2_outlined,
  ),

  /// On the way to the recipient.
  inTransit(
    label: 'In transit',
    color: Color(0xFFF97316),
    icon: Icons.local_shipping_outlined,
  ),

  /// Delivered.
  completed(
    label: 'Completed',
    color: Color(0xFF4ADE80),
    icon: Icons.check_circle_outline,
  ),

  /// Cancelled, failed, or returned.
  cancelled(
    label: 'Cancelled',
    color: Color(0xFFF87171),
    icon: Icons.cancel_outlined,
  );

  const DeliveryStage({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  /// Still needs work from the rider.
  bool get isOpen => this != completed && this != cancelled;

  /// Waiting for the parcel to be collected.
  bool get isBeforePickup => this == assigned || this == accepted;

  /// Parcel is with the rider and moving.
  bool get isOnTheWay => this == pickedUp || this == inTransit;

  static DeliveryStage fromStatus(Object? status) {
    final raw = status?.toString().trim().toLowerCase().replaceAll(
      RegExp(r'[\s-]+'),
      '_',
    );
    if (raw == null || raw.isEmpty) return assigned;

    switch (raw) {
      case 'accepted':
      case 'confirmed':
        return accepted;
      case 'picked_up':
      case 'pickedup':
      case 'pickup':
      case 'collected':
        return pickedUp;
      case 'in_transit':
      case 'intransit':
      case 'on_the_way':
      case 'out_for_delivery':
      case 'shipping':
        return inTransit;
      case 'completed':
      case 'complete':
      case 'delivered':
      case 'done':
        return completed;
      case 'cancelled':
      case 'canceled':
      case 'failed':
      case 'returned':
      case 'rejected':
        return cancelled;
      default:
        // 'pending', 'assigned', 'new' and anything unrecognised are treated as
        // fresh work waiting on the rider.
        return assigned;
    }
  }

  /// Badge text: the word the database stores, tidied up for display.
  static String labelFor(Object? status) {
    final raw = status?.toString().replaceAll('_', ' ').trim();
    if (raw == null || raw.isEmpty) return 'Unknown';
    return raw[0].toUpperCase() + raw.substring(1);
  }
}

/// Dashboard counters, derived from the rider's delivery list so the tiles can
/// never disagree with the deliveries shown underneath them.
class DeliveryStats {
  /// Delivered, all time.
  final int delivered;

  /// Assigned or accepted, parcel not collected yet.
  final int toPickUp;

  /// Picked up or in transit.
  final int onTheWay;

  const DeliveryStats({
    this.delivered = 0,
    this.toPickUp = 0,
    this.onTheWay = 0,
  });

  /// Open work: everything that is neither delivered nor cancelled.
  int get active => toPickUp + onTheWay;

  factory DeliveryStats.fromDeliveries(List<Map<String, dynamic>> deliveries) {
    var delivered = 0;
    var toPickUp = 0;
    var onTheWay = 0;

    for (final delivery in deliveries) {
      final stage = DeliveryStage.fromStatus(delivery['status']);
      if (stage == DeliveryStage.completed) {
        delivered++;
      } else if (stage.isBeforePickup) {
        toPickUp++;
      } else if (stage.isOnTheWay) {
        onTheWay++;
      }
    }

    return DeliveryStats(
      delivered: delivered,
      toPickUp: toPickUp,
      onTheWay: onTheWay,
    );
  }
}
