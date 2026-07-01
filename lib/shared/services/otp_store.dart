import 'package:hive_flutter/hive_flutter.dart';

/// Local-only store for delivery OTPs on the CUSTOMER device.
/// The server keeps only a bcrypt hash (see 04_otp_and_earnings.sql), so the
/// customer app must remember the plaintext it generated to display it in the
/// tracking screen. Stored in Hive, scoped per orderId, cleared on delivery.
class OtpStore {
  static const _box = 'delivery_otps';

  static Future<Box> _open() async => Hive.isBoxOpen(_box)
      ? Hive.box(_box)
      : await Hive.openBox(_box);

  static Future<void> save(String orderId, String otp) async {
    final box = await _open();
    await box.put(orderId, otp);
  }

  static Future<String?> get(String orderId) async {
    final box = await _open();
    return box.get(orderId) as String?;
  }

  static Future<void> clear(String orderId) async {
    final box = await _open();
    await box.delete(orderId);
  }
}
