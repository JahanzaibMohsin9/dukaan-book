import 'package:dukaan_book/app/bootstrap/app_bootstrap.dart';
import 'package:dukaan_book/app/bootstrap/dukaan_book_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  await AppBootstrap.initialize();

  runApp(const ProviderScope(child: DukaanBookApp()));
}
