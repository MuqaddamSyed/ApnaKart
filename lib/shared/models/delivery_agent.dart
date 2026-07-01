/// Maps the `delivery_agents` table.
class DeliveryAgent {
  final String id;
  final bool isVerified;
  final bool isAvailable;
  final double? currentLat;
  final double? currentLng;
  final String? vehicleType;
  final String? address;
  final int totalDeliveries;
  final double earningsToday;

  DeliveryAgent({
    required this.id,
    this.isVerified = false,
    this.isAvailable = false,
    this.currentLat,
    this.currentLng,
    this.vehicleType,
    this.address,
    this.totalDeliveries = 0,
    this.earningsToday = 0,
  });

  factory DeliveryAgent.fromMap(Map<String, dynamic> m) => DeliveryAgent(
        id: m['id'] as String,
        isVerified: m['is_verified'] as bool? ?? false,
        isAvailable: m['is_available'] as bool? ?? false,
        currentLat: (m['current_lat'] as num?)?.toDouble(),
        currentLng: (m['current_lng'] as num?)?.toDouble(),
        vehicleType: m['vehicle_type'] as String?,
        address: m['address'] as String?,
        totalDeliveries: m['total_deliveries'] as int? ?? 0,
        earningsToday: (m['earnings_today'] as num?)?.toDouble() ?? 0,
      );
}
