import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  static const _dbName = 'dantiko_lb.db';
  static const _dbVersion = 3;

  static Database? _database;

  static Future<Database> get instance async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static String? _configuredDatabasePath;
  static Future<void>? _configuration;

  /// Use one stable location in debug and packaged Windows releases.
  /// Never move or delete an existing database.
  static Future<void> configureDatabaseLocation() =>
      _configuration ??= _configureDatabaseLocation();

  static Future<void> _configureDatabaseLocation() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    late final Directory rootDir;
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) {
        throw StateError('APPDATA is not available; cannot locate saved loadouts.');
      }
      rootDir = Directory(p.join(appData, 'Dantiko', 'DantikoLB'));
    } else {
      final appSupport = await getApplicationSupportDirectory();
      rootDir = Directory(p.join(appSupport.parent.path, 'DantikoLB'));
    }

    final dataDir = Directory(p.join(rootDir.path, 'data'));
    final exportDir = Directory(p.join(rootDir.path, 'exports'));
    await dataDir.create(recursive: true);
    await exportDir.create(recursive: true);

    _configuredDatabasePath = p.join(dataDir.path, _dbName);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      databaseFactoryFfi.setDatabasesPath(dataDir.path);
    }
  }

  static Future<Database> _initDatabase() async {
    await configureDatabaseLocation();
    final path = _configuredDatabasePath!;
    // This is the original user-data location, including Dantiko/DantikoLB.
    // Existing databases are opened and migrated in place.
    return await openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Characters
    await db.execute('''
      CREATE TABLE characters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        combat_style TEXT,
        discipline TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    // Loadouts
    await db.execute('''
      CREATE TABLE loadouts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        character_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        combat_style TEXT,
        discipline TEXT,
        role TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(character_id) REFERENCES characters(id) ON DELETE CASCADE
      );
    ''');

    await db.execute(
        'CREATE INDEX idx_loadouts_character_id ON loadouts(character_id);');
    await db.execute(
        'CREATE INDEX idx_loadouts_discipline ON loadouts(discipline);');
    await db.execute(
        'CREATE INDEX idx_loadouts_role ON loadouts(role);');

    // Loadout Slots
    await db.execute('''
      CREATE TABLE loadout_slots (
        loadout_id INTEGER NOT NULL,
        slot TEXT NOT NULL,
        rating INTEGER NOT NULL,
        focus TEXT NOT NULL,
        augment_key TEXT NOT NULL,
        preferred_profile TEXT NOT NULL,
        crystal_key TEXT,
        relic_effect TEXT,
        relic_active INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(loadout_id, slot),
        FOREIGN KEY(loadout_id) REFERENCES loadouts(id) ON DELETE CASCADE
      );
    ''');

    await db.execute(
        'CREATE INDEX idx_loadout_slots_loadout_id ON loadout_slots(loadout_id);');

    // Optional: global stim storage
    await db.execute('''
      CREATE TABLE loadout_globals (
        loadout_id INTEGER PRIMARY KEY,
        stim_key TEXT NOT NULL,
        crystal_main_key TEXT NOT NULL,
        crystal_off_key TEXT NOT NULL,
        FOREIGN KEY(loadout_id) REFERENCES loadouts(id) ON DELETE CASCADE
      );
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      // Some existing databases already contain one or both relic columns
      // even though their SQLite user_version is older than 3.
      final columns = await db.rawQuery('PRAGMA table_info(loadout_slots)');
      final columnNames = columns.map((row) => row['name'] as String).toSet();

      if (!columnNames.contains('relic_effect')) {
        await db.execute('ALTER TABLE loadout_slots ADD COLUMN relic_effect TEXT;');
      }
      if (!columnNames.contains('relic_active')) {
        await db.execute(
          'ALTER TABLE loadout_slots ADD COLUMN relic_active INTEGER NOT NULL DEFAULT 0;',
        );
      }
    }
    if (oldVersion < 2) {
      // Recreate loadout_globals with crystals (simple migration)
      await db.execute('DROP TABLE IF EXISTS loadout_globals;');
      await db.execute('''
        CREATE TABLE loadout_globals (
          loadout_id INTEGER PRIMARY KEY,
          stim_key TEXT NOT NULL,
          crystal_main_key TEXT NOT NULL,
          crystal_off_key TEXT NOT NULL,
          FOREIGN KEY(loadout_id) REFERENCES loadouts(id) ON DELETE CASCADE
        );
      ''');
    }
  }
}