class Token {
  final String oracleId;
  final String name;
  final String imageUri;
  final String? firstPrintingImageUri;

  Token({
    required this.oracleId,
    required this.name,
    required this.imageUri,
    this.firstPrintingImageUri,
  });

  Map<String, Object?> toMap() {
    var map = {
      'oracle_id': oracleId,
      'name': name,
      'image_uri': imageUri,
      'first_printing_image_uri': firstPrintingImageUri
    };
    return map;
  }
}