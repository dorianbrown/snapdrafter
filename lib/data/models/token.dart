class Token {
  final String oracleId;
  final String name;
  final String imageUri;

  Token({
    required this.oracleId,
    required this.name,
    required this.imageUri,
  });

  Map<String, Object?> toMap() {
    var map = {
      'oracle_id': oracleId,
      'name': name,
      'image_uri': imageUri
    };
    return map;
  }
}