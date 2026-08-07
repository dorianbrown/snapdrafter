class Token {
  final String oracleId;
  final String name;
  final String imageUri;
  final String? firstPrintingImageUri;
  final String? imageSetCode;
  final String? firstPrintingSetCode;

  Token({
    required this.oracleId,
    required this.name,
    required this.imageUri,
    this.firstPrintingImageUri,
    this.imageSetCode,
    this.firstPrintingSetCode,
  });

  Map<String, Object?> toMap() {
    var map = {
      'oracle_id': oracleId,
      'name': name,
      'image_uri': imageUri,
      'first_printing_image_uri': firstPrintingImageUri,
      'image_set_code': imageSetCode,
      'first_printing_set_code': firstPrintingSetCode
    };
    return map;
  }
}