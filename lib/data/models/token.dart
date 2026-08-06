class Token {
  final String oracleId;
  final String name;
  final String imageUri;
  final String? ubImageUri;
  final String? nonUbImageUri;

  Token({
    required this.oracleId,
    required this.name,
    required this.imageUri,
    this.ubImageUri,
    this.nonUbImageUri,
  });

  Map<String, Object?> toMap() {
    var map = {
      'oracle_id': oracleId,
      'name': name,
      'image_uri': imageUri,
      'ub_image_uri': ubImageUri,
      'non_ub_image_uri': nonUbImageUri
    };
    return map;
  }
}