class Set {
  final String code;
  final String name;
  final String releasedAt;

  const Set({
    required this.code,
    required this.name,
    required this.releasedAt
  });

  Map<String, Object?> toMap() {
    var map = {'code': code, 'name': name, 'releasedAt': releasedAt};
    return map;
  }

  @override
  String toString() {
    return 'DecklistEntry{code: $code, name: $name, releasedAt: $releasedAt}';
  }
}