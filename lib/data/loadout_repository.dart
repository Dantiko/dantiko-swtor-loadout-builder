import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../services/enums.dart'; // GearSlot, StatFocus
import '../services/key_builders.dart' show PreferredProfile;

/// ------------------------------------------------------------
/// Models
/// ------------------------------------------------------------

class CharacterRow {
  final int id;
  final String name;
  final String? combatStyle;
  final String? discipline;
  final int createdAt;
  final int updatedAt;

  const CharacterRow({
    required this.id,
    required this.name,
    required this.combatStyle,
    required this.discipline,
    required this.createdAt,
    required this.updatedAt,
  });

  static CharacterRow fromMap(Map<String, Object?> m) => CharacterRow(
        id: (m['id'] as int),
        name: (m['name'] as String),
        combatStyle: (m['combat_style'] as String?),
        discipline: (m['discipline'] as String?),
        createdAt: (m['created_at'] as int),
        updatedAt: (m['updated_at'] as int),
      );
}

class LoadoutSummary {
  final int id;
  final int characterId;
  final String name;
  final String? combatStyle;
  final String? discipline;
  final String? role;
  final String? notes;
  final int createdAt;
  final int updatedAt;

  const LoadoutSummary({
    required this.id,
    required this.characterId,
    required this.name,
    required this.combatStyle,
    required this.discipline,
    required this.role,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  static LoadoutSummary fromMap(Map<String, Object?> m) => LoadoutSummary(
        id: (m['id'] as int),
        characterId: (m['character_id'] as int),
        name: (m['name'] as String),
        combatStyle: (m['combat_style'] as String?),
        discipline: (m['discipline'] as String?),
        role: (m['role'] as String?),
        notes: (m['notes'] as String?),
        createdAt: (m['created_at'] as int),
        updatedAt: (m['updated_at'] as int),
      );
}

class LoadoutSlotRow {
  final GearSlot slot;
  final int rating; // 0 => none
  final StatFocus focus;
  final String augmentKey; // 'AUG_NONE' etc.
  final PreferredProfile preferredProfile; // AUTO/DPS/TANK
  final String? crystalKey; // only for MAIN_HAND/OFF_HAND if you use it

  const LoadoutSlotRow({
    required this.slot,
    required this.rating,
    required this.focus,
    required this.augmentKey,
    required this.preferredProfile,
    required this.crystalKey,
  });

  static LoadoutSlotRow fromMap(Map<String, Object?> m) => LoadoutSlotRow(
        slot: GearSlot.values.byName(m['slot'] as String),
        rating: (m['rating'] as int),
        focus: StatFocus.values.byName(m['focus'] as String),
        augmentKey: (m['augment_key'] as String),
        preferredProfile: PreferredProfile.values.byName(m['preferred_profile'] as String),
        crystalKey: (m['crystal_key'] as String?),
      );
}

class LoadoutGlobalsRow {
  final String stimKey;
  final String crystalMainKey;
  final String crystalOffKey;

  const LoadoutGlobalsRow({
    required this.stimKey,
    required this.crystalMainKey,
    required this.crystalOffKey,
  });

  static LoadoutGlobalsRow fromMap(Map<String, Object?> m) => LoadoutGlobalsRow(
        stimKey: (m['stim_key'] as String),
        crystalMainKey: (m['crystal_main_key'] as String),
        crystalOffKey: (m['crystal_off_key'] as String),
      );
}

class LoadoutFull {
  final LoadoutSummary meta;
  final String? notes;
  final LoadoutGlobalsRow globals;
  final Map<GearSlot, LoadoutSlotRow> slots;

  const LoadoutFull({
    required this.meta,
    required this.notes,
    required this.globals,
    required this.slots,
  });
}

/// Draft used by UI to save a loadout.
class LoadoutDraft {
  final int? id;
  final int characterId;
  final String name;

  final String? combatStyle;
  final String? discipline;
  final String? role;
  final String? notes;

  final String stimKey;
  final String crystalMainKey;
  final String crystalOffKey;

  final List<LoadoutSlotRow> slotRows;

  const LoadoutDraft({
    this.id,
    required this.characterId,
    required this.name,
    required this.combatStyle,
    required this.discipline,
    required this.role,
    required this.notes,
    required this.stimKey,
    required this.crystalMainKey,
    required this.crystalOffKey,
    required this.slotRows,
  });
}

/// ------------------------------------------------------------
/// Repository
/// ------------------------------------------------------------

class LoadoutRepository {
  Future<Database> get _db async => AppDatabase.instance;

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  // -------------------------
  // Characters
  // -------------------------

  Future<int> createCharacter({
    required String name,
    String? combatStyle,
    String? discipline,
  }) async {
    final db = await _db;
    final now = _nowMs();

    return db.insert('characters', {
      'name': name,
      'combat_style': combatStyle,
      'discipline': discipline,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateCharacter({
    required int id,
    String? name,
    String? combatStyle,
    String? discipline,
  }) async {
    final db = await _db;
    final now = _nowMs();

    final values = <String, Object?>{
      'updated_at': now,
    };
    if (name != null) values['name'] = name;
    if (combatStyle != null) values['combat_style'] = combatStyle;
    if (discipline != null) values['discipline'] = discipline;

    await db.update(
      'characters',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<CharacterRow>> listCharacters() async {
    final db = await _db;
    final rows = await db.query(
      'characters',
      orderBy: 'updated_at DESC',
    );
    return rows.map(CharacterRow.fromMap).toList(growable: false);
  }

  Future<void> deleteCharacter(int id) async {
    final db = await _db;
    await db.delete('characters', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------
  // Loadouts
  // -------------------------

  /// Insert or update a loadout + its slot rows + globals in a single transaction.
  Future<int> saveLoadout(LoadoutDraft draft) async {
    final db = await _db;
    final now = _nowMs();

    return db.transaction<int>((txn) async {
      int loadoutId;

      if (draft.id == null) {
        loadoutId = await txn.insert('loadouts', {
          'character_id': draft.characterId,
          'name': draft.name,
          'combat_style': draft.combatStyle,
          'discipline': draft.discipline,
          'role': draft.role,
          'notes': draft.notes,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        loadoutId = draft.id!;
        await txn.update(
          'loadouts',
          {
            'character_id': draft.characterId,
            'name': draft.name,
            'combat_style': draft.combatStyle,
            'discipline': draft.discipline,
            'role': draft.role,
            'notes': draft.notes,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [loadoutId],
        );

        // clear old slots + globals to avoid drift
        await txn.delete('loadout_slots', where: 'loadout_id = ?', whereArgs: [loadoutId]);
        await txn.delete('loadout_globals', where: 'loadout_id = ?', whereArgs: [loadoutId]);
      }

      // globals
      await txn.insert('loadout_globals', {
        'loadout_id': loadoutId,
        'stim_key': draft.stimKey,
        'crystal_main_key': draft.crystalMainKey,
        'crystal_off_key': draft.crystalOffKey,
      });

      // slots
      for (final r in draft.slotRows) {
        await txn.insert('loadout_slots', {
          'loadout_id': loadoutId,
          'slot': r.slot.name,
          'rating': r.rating,
          'focus': r.focus.name,
          'augment_key': r.augmentKey,
          'preferred_profile': r.preferredProfile.name,
          'crystal_key': r.crystalKey,
        });
      }

      return loadoutId;
    });
  }

  Future<void> deleteLoadout(int loadoutId) async {
    final db = await _db;
    await db.delete('loadouts', where: 'id = ?', whereArgs: [loadoutId]);
    // slots/globals cascade via FK (and we also delete explicitly in update path)
  }

  /// Search loadouts with optional filters.
  /// - [characterId] to scope to one character
  /// - [query] matches name (case-insensitive-ish) and notes
  /// - [discipline] exact match
  /// - [role] exact match
  Future<List<LoadoutSummary>> searchLoadouts({
    int? characterId,
    String? query,
    String? discipline,
    String? role,
    int limit = 100,
  }) async {
    final db = await _db;

    final where = <String>[];
    final args = <Object?>[];

    if (characterId != null) {
      where.add('character_id = ?');
      args.add(characterId);
    }
    if (discipline != null && discipline.isNotEmpty) {
      where.add('discipline = ?');
      args.add(discipline);
    }
    if (role != null && role.isNotEmpty) {
      where.add('role = ?');
      args.add(role);
    }
    if (query != null && query.trim().isNotEmpty) {
      // LIKE on name + notes
      where.add('(name LIKE ? OR notes LIKE ?)');
      final q = '%${query.trim()}%';
      args.add(q);
      args.add(q);
    }

    final rows = await db.query(
      'loadouts',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC',
      limit: limit,
    );

    return rows.map(LoadoutSummary.fromMap).toList(growable: false);
  }

  Future<LoadoutFull?> getLoadout(int loadoutId) async {
    final db = await _db;

    final loadoutRows = await db.query(
      'loadouts',
      where: 'id = ?',
      whereArgs: [loadoutId],
      limit: 1,
    );
    if (loadoutRows.isEmpty) return null;

    final meta = LoadoutSummary.fromMap(loadoutRows.first);
    final notes = loadoutRows.first['notes'] as String?;

    final globalsRows = await db.query(
      'loadout_globals',
      where: 'loadout_id = ?',
      whereArgs: [loadoutId],
      limit: 1,
    );

    // If globals row missing for some reason, fall back to STIM_NONE
    final globals = globalsRows.isNotEmpty
        ? LoadoutGlobalsRow.fromMap(globalsRows.first)
        : const LoadoutGlobalsRow(
            stimKey: 'STIM_NONE',
            crystalMainKey: 'CRYSTAL_NONE',
            crystalOffKey: 'CRYSTAL_NONE',
          );

    final slotRows = await db.query(
      'loadout_slots',
      where: 'loadout_id = ?',
      whereArgs: [loadoutId],
    );

    final slots = <GearSlot, LoadoutSlotRow>{};
    for (final r in slotRows) {
      final row = LoadoutSlotRow.fromMap(r);
      slots[row.slot] = row;
    }

    return LoadoutFull(
      meta: meta,
      notes: notes,
      globals: globals,
      slots: slots,
    );
  }

  Future<int> duplicateLoadout(int sourceLoadoutId, {String? newName}) async {
  final db = await _db;
  final now = _nowMs();

    return db.transaction<int>((txn) async {
      final loadRows = await txn.query(
        'loadouts',
        where: 'id = ?',
        whereArgs: [sourceLoadoutId],
        limit: 1,
      );
      if (loadRows.isEmpty) {
        throw StateError('Loadout not found: $sourceLoadoutId');
      }
      final src = loadRows.first;

      final globalsRows = await txn.query(
        'loadout_globals',
        where: 'loadout_id = ?',
        whereArgs: [sourceLoadoutId],
        limit: 1,
      );

      final slotRows = await txn.query(
        'loadout_slots',
        where: 'loadout_id = ?',
        whereArgs: [sourceLoadoutId],
      );

      final String srcName = (src['name'] as String);
      final String copyName = (newName != null && newName.trim().isNotEmpty)
          ? newName.trim()
          : '$srcName (Copy)';

      // Insert new loadout meta
      final newId = await txn.insert('loadouts', {
        'character_id': src['character_id'],
        'name': copyName,
        'combat_style': src['combat_style'],
        'discipline': src['discipline'],
        'role': src['role'],
        'notes': src['notes'],
        'created_at': now,
        'updated_at': now,
      });

      // Copy globals (stim + crystals)
      if (globalsRows.isNotEmpty) {
        final g = globalsRows.first;
        await txn.insert('loadout_globals', {
          'loadout_id': newId,
          'stim_key': g['stim_key'],
          'crystal_main_key': g['crystal_main_key'],
          'crystal_off_key': g['crystal_off_key'],
        });
      } else {
        // fallback if missing
        await txn.insert('loadout_globals', {
          'loadout_id': newId,
          'stim_key': 'STIM_NONE',
          'crystal_main_key': 'CRYSTAL_NONE',
          'crystal_off_key': 'CRYSTAL_NONE',
        });
      }

      // Copy slots
      for (final r in slotRows) {
        await txn.insert('loadout_slots', {
          'loadout_id': newId,
          'slot': r['slot'],
          'rating': r['rating'],
          'focus': r['focus'],
          'augment_key': r['augment_key'],
          'preferred_profile': r['preferred_profile'],
          'crystal_key': r['crystal_key'],
        });
      }

      return newId;
    });
  }

  Future<List<LoadoutSummary>> listLoadoutsForCharacter(int characterId) async {
    return searchLoadouts(characterId: characterId, limit: 10000);
  }

  Future<void> updateLoadoutMeta({
    required int loadoutId,
    String? name,
    int? characterId,
    String? combatStyle,
    String? discipline,
    String? role,
    String? notes,
    bool setNotes = false,
  }) async {
    final db = await _db;
    final now = _nowMs();

    final values = <String, Object?>{'updated_at': now};

    if (name != null) values['name'] = name;
    if (characterId != null) values['character_id'] = characterId;
    if (combatStyle != null) values['combat_style'] = combatStyle;
    if (discipline != null) values['discipline'] = discipline;
    if (role != null) values['role'] = role;

    // ✅ allow setting notes to NULL
    if (setNotes) values['notes'] = notes;

    await db.update('loadouts', values, where: 'id = ?', whereArgs: [loadoutId]);
  }
}