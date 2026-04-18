class TransportOption {
  final String name;
  final String emoji;

  const TransportOption({
    required this.name,
    required this.emoji,
  });
}

class TransportOptions {
  static const List<TransportOption> items = [
    TransportOption(name: 'Đi bộ', emoji: '🚶'),
    TransportOption(name: 'Xe đạp', emoji: '🚲'),
    TransportOption(name: 'Xe máy', emoji: '🏍️'),
    TransportOption(name: 'Ô tô', emoji: '🚗'),
    TransportOption(name: 'Xe buýt', emoji: '🚌'),
    TransportOption(name: 'Tàu hỏa', emoji: '🚆'),
    TransportOption(name: 'Tàu thủy', emoji: '⛵'),
    TransportOption(name: 'Máy bay', emoji: '✈️'),
  ];
}