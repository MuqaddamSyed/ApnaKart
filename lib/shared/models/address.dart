/// Maps the `addresses` table.
class Address {
  final String id;
  final String customerId;
  final String? label;
  final String? fullAddress;
  final double? lat;
  final double? lng;

  Address({
    required this.id,
    required this.customerId,
    this.label,
    this.fullAddress,
    this.lat,
    this.lng,
  });

  factory Address.fromMap(Map<String, dynamic> m) => Address(
        id: m['id'] as String,
        customerId: m['customer_id'] as String,
        label: m['label'] as String?,
        fullAddress: m['full_address'] as String?,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'customer_id': customerId,
        'label': label,
        'full_address': fullAddress,
        'lat': lat,
        'lng': lng,
      };
}
