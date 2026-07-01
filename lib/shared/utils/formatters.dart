import 'package:intl/intl.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 0);
final _date = DateFormat('dd MMM, hh:mm a');

String formatRupees(num v) => _rupee.format(v);
String formatDate(DateTime d) => _date.format(d.toLocal());

/// Discount % helper mirroring the DB trigger.
int discountPercent(num mrp, num sale) =>
    mrp <= 0 ? 0 : (((mrp - sale) / mrp) * 100).round();
