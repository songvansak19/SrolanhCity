/// Pure bilingual (Khmer / English) relative timestamp, short-date, and
/// withdrawal countdown formatter.
abstract final class RelativeTimeFormatter {
  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const List<String> _khmerDigits = [
    '០',
    '១',
    '២',
    '៣',
    '៤',
    '៥',
    '៦',
    '៧',
    '៨',
    '៩',
  ];

  /// Converts ASCII digits in [value] to Khmer numerals (`០`–`៩`).
  static String toKhmerDigits(int value) {
    final raw = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final unit = raw.codeUnitAt(i);
      if (unit >= 48 && unit <= 57) {
        buffer.write(_khmerDigits[unit - 48]);
      } else {
        buffer.writeCharCode(unit);
      }
    }
    return buffer.toString();
  }

  /// Formats [timestamp] relative to [now] (defaults to `DateTime.now()`).
  static String formatRelative(
    DateTime timestamp, {
    required bool englishFirst,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final diff = reference.difference(timestamp);

    if (diff.isNegative || diff.inSeconds < 60) {
      return englishFirst ? 'Just now' : 'ឥឡូវនេះ';
    }
    if (diff.inMinutes < 60) {
      final mins = diff.inMinutes;
      return englishFirst ? '${mins}m ago' : '${toKhmerDigits(mins)} នាទីមុន';
    }
    if (diff.inHours < 24) {
      final hours = diff.inHours;
      return englishFirst ? '${hours}h ago' : '${toKhmerDigits(hours)} ម៉ោងមុន';
    }
    if (diff.inDays == 1) {
      return englishFirst ? 'Yesterday' : 'ម្សិលមិញ';
    }
    if (diff.inDays < 7) {
      final days = diff.inDays;
      return englishFirst ? '${days}d ago' : '${toKhmerDigits(days)} ថ្ងៃមុន';
    }
    return formatShortDate(timestamp);
  }

  /// Formats [dt] as `'23 Nov'`.
  static String formatShortDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day} ${_months[local.month - 1]}';
  }

  /// Formats [dt] as `'23 Nov, 12:33'`.
  static String formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${formatShortDate(local)}, $hh:$mm';
  }

  /// Formats a remaining duration as `MM:SS` (e.g., `'14:32'`).
  static String formatCountdown(Duration remaining) {
    final totalSeconds = remaining.inSeconds < 0 ? 0 : remaining.inSeconds;
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  /// Formats compact remaining grace time for list badges (e.g., `'15m'` / `'១៥ នាទី'`).
  static String formatCompactRemaining(
    Duration remaining, {
    required bool englishFirst,
  }) {
    final totalSeconds = remaining.inSeconds < 0 ? 0 : remaining.inSeconds;
    if (totalSeconds >= 60) {
      final mins = (totalSeconds / 60).ceil();
      return englishFirst ? '${mins}m' : '${toKhmerDigits(mins)} នាទី';
    }
    return englishFirst
        ? '${totalSeconds}s'
        : '${toKhmerDigits(totalSeconds)} វិ.';
  }
}
