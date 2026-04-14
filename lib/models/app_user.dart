class AppUser {
  final String username;
  final String password;
  final String fullName;
  final String email;

  const AppUser({
    required this.username,
    required this.password,
    required this.fullName,
    required this.email,
  });

  AppUser copyWith({
    String? username,
    String? password,
    String? fullName,
    String? email,
  }) {
    return AppUser(
      username: username ?? this.username,
      password: password ?? this.password,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
    );
  }
}