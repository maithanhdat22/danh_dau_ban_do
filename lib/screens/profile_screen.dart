import 'package:flutter/material.dart';
import '../models/app_user.dart';

class ProfileScreen extends StatelessWidget {
  final AppUser user;
  final VoidCallback onLogout;

  const ProfileScreen({
    super.key,
    required this.user,
    required this.onLogout,
  });

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title),
        subtitle: Text(value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        const CircleAvatar(
          radius: 48,
          child: Icon(Icons.person, size: 50),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            user.fullName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 24),
        _buildInfoCard(
          icon: Icons.person_outline,
          title: 'Tên đăng nhập',
          value: user.username,
        ),
        _buildInfoCard(
          icon: Icons.email_outlined,
          title: 'Email',
          value: user.email,
        ),
        _buildInfoCard(
          icon: Icons.badge_outlined,
          title: 'Họ và tên',
          value: user.fullName,
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Đăng xuất'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
      ],
    );
  }
}