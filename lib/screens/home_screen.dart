import 'package:flutter/material.dart';
import '../widgets/map_widget.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Travel Map'),
      ),
      body: MapWidget(
        currentUsername: '',
        onPlaceSaved: (value) {},
      ),
    );
  }
}
