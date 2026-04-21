import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/place_marker.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'map_tab_screen.dart';
import 'profile_screen.dart';
import 'saved_places_screen.dart';

class DashboardScreen extends StatefulWidget {
  final AppUser user;

  const DashboardScreen({
    super.key,
    required this.user,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  final List<PlaceMarker> _savedPlaces = [];

  void _addPlace(PlaceMarker place) {
    setState(() {
      _savedPlaces.add(place);
    });
  }

  void _removePlace(int index) {
    setState(() {
      _savedPlaces.removeAt(index);
    });
  }

  void _logout() {
    AuthService.logout().whenComplete(() {
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      MapTabScreen(
        user: widget.user,
        onPlaceSaved: _addPlace,
      ),
      SavedPlacesScreen(
        places: _savedPlaces,
        onDelete: _removePlace,
      ),
      ProfileScreen(
        user: widget.user,
        onLogout: _logout,
      ),
    ];

    final titles = ['Ban do', 'Dia diem da luu', 'Tai khoan'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_currentIndex]),
        centerTitle: true,
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Ban do',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Da luu',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Tai khoan',
          ),
        ],
      ),
    );
  }
}
