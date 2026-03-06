import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'services/asset_repository.dart';
import 'ui/gear_layout_screen.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite for desktop
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 763),
    minimumSize: Size(1200, 763),
    center: true,
    title: "Dantiko's SWTOR Loadout Builder",
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  windowManager.addListener(AspectRatioEnforcer());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Dantiko's SWTOR Loadout Builder",
      theme: ThemeData(useMaterial3: true),
      home: const _Bootstrap(),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  AssetRepository? repo;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AssetRepository.load();
      setState(() => repo = r);
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Scaffold(
        body: Center(child: Text('Error: $error')),
      );
    }
    if (repo == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return GearLayoutScreen(repo: repo!);
  }
}

class AspectRatioEnforcer with WindowListener {
  static const double ratio = 1.573;

  @override
  void onWindowResize() async {
    final size = await windowManager.getSize();

    final double width = size.width;
    final double height = size.height;

    final double currentRatio = width / height;

    if (currentRatio < ratio) {
      final newWidth = height * ratio;
      await windowManager.setSize(Size(newWidth, height));
    }
  }
}