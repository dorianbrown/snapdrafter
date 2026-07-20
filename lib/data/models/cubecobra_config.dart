class CubeCobraCredentials {
  final String cubeId;
  final String username;
  final String cookie;

  const CubeCobraCredentials({
    required this.cubeId,
    required this.username,
    required this.cookie,
  });

  Map<String, dynamic> toJson() => {
    'cubeId': cubeId,
    'username': username,
    'cookie': cookie,
  };

  factory CubeCobraCredentials.fromJson(Map<String, dynamic> json) {
    return CubeCobraCredentials(
      cubeId: json['cubeId'] as String,
      username: json['username'] as String,
      cookie: json['cookie'] as String,
    );
  }
}
