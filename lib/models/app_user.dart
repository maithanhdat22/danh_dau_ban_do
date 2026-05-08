class AppUser {
  final String uid;
  final String username;
  final String fullName;
  final String email;

  const AppUser({
    required this.uid,
    required this.username,
    required this.fullName,
    required this.email,
  });

  AppUser copyWith({
    String? uid,
    String? username,
    String? fullName,
    String? email,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
    );
  }
}
