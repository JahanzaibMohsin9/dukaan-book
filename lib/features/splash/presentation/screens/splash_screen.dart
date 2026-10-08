import 'package:dukaan_book/core/widgets/placeholder_screen.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Dukaan Book',
      subtitle: 'Opening the shop ledger and checking the local-first setup.',
      highlight: 'Splash route is the app entry point.',
    );
  }
}
