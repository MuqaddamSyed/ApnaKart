/// Maps the `users` table.
class AppUser {
  final String id;
  final String? phone;
  final String? email;
  final String? name;
  final String? role; // customer|supplier|delivery|admin
  final bool isActive;

  AppUser({
    required this.id,
    this.phone,
    this.email,
    this.name,
    this.role,
    this.isActive = true,
  });

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        phone: m['phone'] as String?,
        email: m['email'] as String?,
        name: m['name'] as String?,
        role: m['role'] as String?,
        isActive: m['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'phone': phone,
        'email': email,
        'name': name,
        'role': role,
        'is_active': isActive,
      };
}
