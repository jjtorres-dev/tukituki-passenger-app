class PublicUser {
  const PublicUser({
    required this.id,
    required this.phoneE164,
    required this.roles,
    required this.status,
    required this.isPhoneVerified,
    required this.createdAt,
  });

  final String id;
  final String phoneE164;
  final List<String> roles;
  final String status;
  final bool isPhoneVerified;
  final DateTime createdAt;

  factory PublicUser.fromJson(
    Map<String, dynamic> json,
  ) {
    return PublicUser(
      id: json['id'] as String,
      phoneE164: json['phoneE164'] as String,
      roles: (json['roles'] as List<dynamic>)
          .map((role) => role.toString())
          .toList(),
      status: json['status'] as String,
      isPhoneVerified: json['isPhoneVerified'] as bool,
      createdAt: DateTime.parse(
        json['createdAt'] as String,
      ),
    );
  }
}