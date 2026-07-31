/// Thousands separators for gold amounts.
///
/// Gold runs to six figures (the biggest charge tier is 300,000), and an
/// unseparated "300000" beside a "30000" is genuinely hard to tell apart at a
/// glance — which is the whole job of a price.
///
/// Written out rather than pulled from intl's NumberFormat so it needs no
/// locale to be loaded: every locale this app ships (ko/en/de) groups by three,
/// and the separator is a comma in all of them.
String formatGold(Object? value) {
  final n = value is int ? value : int.tryParse('$value') ?? 0;
  final negative = n < 0;
  final digits = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return negative ? '-$buf' : buf.toString();
}
