int? fareAmountInCents(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$').firstMatch(normalized);

  if (match == null) {
    return null;
  }

  final wholePart = int.tryParse(match.group(2)!);
  final fraction = match.group(3) ?? '';

  if (wholePart == null ||
      (fraction.length > 2 &&
          fraction.substring(2).contains(RegExp(r'[1-9]')))) {
    return null;
  }

  final centsPart = int.tryParse(fraction.padRight(2, '0').substring(0, 2));

  if (centsPart == null) {
    return null;
  }

  final amount = wholePart * 100 + centsPart;

  return match.group(1) == '-' ? -amount : amount;
}

bool? fareAmountsDiffer(String first, String second) {
  final firstCents = fareAmountInCents(first);
  final secondCents = fareAmountInCents(second);

  if (firstCents == null || secondCents == null) {
    return null;
  }

  return firstCents != secondCents;
}

String? normalizePassengerOfferFare(String value) {
  final normalized = value.trim().replaceAll(',', '.');

  if (!RegExp(r'^\+?(?:\d+(?:\.\d{0,2})?|\.\d{1,2})$').hasMatch(normalized)) {
    return null;
  }

  final amountInCents = fareAmountInCents(normalized);

  if (amountInCents == null || amountInCents <= 0 || amountInCents > 999999) {
    return null;
  }

  final wholePart = amountInCents ~/ 100;
  final centsPart = (amountInCents % 100).toString().padLeft(2, '0');

  return '$wholePart.$centsPart';
}
