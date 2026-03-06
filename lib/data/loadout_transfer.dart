import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../data/loadout_repository.dart';
import '../services/enums.dart';
import '../services/key_builders.dart' show PreferredProfile;

class LoadoutTransfer {
  final LoadoutRepository repo;
  LoadoutTransfer(this.repo);

  // -----------------------
  // Export: single loadout
  // -----------------------
  Future<String> exportLoadoutToJson(int loadoutId) async {
    final full = await repo.getLoadout(loadoutId);
    if (full == null) {
      throw StateError('Loadout not found: $loadoutId');
    }

    final payload = _fullToPayload(full);

    // IMPORTANT: checksum over payload JSON only
    final payloadJson = jsonEncode(payload);
    final checksum = sha256.convert(utf8.encode(payloadJson)).toString();

    final wrapper = <String, Object?>{
      'version': 1,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'payload': payload,
      'checksum': checksum,
    };

    return const JsonEncoder.withIndent('  ').convert(wrapper);
  }

  Map<String, Object?> _fullToPayload(LoadoutFull full) {
    // Build payload map in a stable key order
    final slots = <Object?>[];
    final slotRows = full.slots.values.toList()
      ..sort((a, b) => a.slot.index.compareTo(b.slot.index));

    for (final row in slotRows) {
      slots.add({
        'slot': row.slot.name,
        'rating': row.rating,
        'focus': row.focus.name,
        'augmentKey': row.augmentKey,
        'preferredProfile': row.preferredProfile.name,
      });
    }

    return <String, Object?>{
      'name': full.meta.name,
      'combatStyle': full.meta.combatStyle,
      'discipline': full.meta.discipline,
      'role': full.meta.role,
      'notes': full.notes,
      'stimKey': full.globals.stimKey,
      'crystalMainKey': full.globals.crystalMainKey,
      'crystalOffKey': full.globals.crystalOffKey,
      'slots': slots,
    };
  }

  // -----------------------
  // Import: single loadout
  // -----------------------
  Future<void> importSingleLoadoutJson(
    String jsonStr, {
    required int targetCharacterId,
  }) async {
    final dynamic decoded = json.decode(jsonStr);
    if (decoded is! Map) {
      throw const FormatException('Invalid JSON: expected an object at root.');
    }

    final version = decoded['version'];
    if (version != 1) {
      throw FormatException('Unsupported export version: $version');
    }

    final payload = decoded['payload'];
    final checksum = decoded['checksum'];

    if (payload is! Map) {
      throw const FormatException('Invalid file: missing payload.');
    }
    if (checksum is! String || checksum.isEmpty) {
      throw const FormatException('Invalid file: missing checksum.');
    }

    // Verify checksum
    final payloadJson = jsonEncode(payload);
    final expected = sha256.convert(utf8.encode(payloadJson)).toString();
    if (expected != checksum) {
      throw const FormatException('Checksum mismatch. File may be corrupted or edited.');
    }

    // Validate required fields
    final name = (payload['name'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      throw const FormatException('Invalid payload: missing loadout name.');
    }

    final stimKey = (payload['stimKey'] as String?) ?? 'STIM_NONE';
    final crystalMainKey = (payload['crystalMainKey'] as String?) ?? 'CRYSTAL_NONE';
    final crystalOffKey = (payload['crystalOffKey'] as String?) ?? 'CRYSTAL_NONE';

    final slots = payload['slots'];
    if (slots is! List) {
      throw const FormatException('Invalid payload: slots must be a list.');
    }

    final slotRows = <LoadoutSlotRow>[];
    for (final s in slots) {
      if (s is! Map) continue;

      final slotName = s['slot'] as String?;
      if (slotName == null) continue;

      final rating = (s['rating'] is int) ? (s['rating'] as int) : 0;
      final focusName = (s['focus'] as String?) ?? StatFocus.NONE.name;
      final augmentKey = (s['augmentKey'] as String?) ?? 'AUG_NONE';
      final prefName = (s['preferredProfile'] as String?) ?? PreferredProfile.AUTO.name;

      slotRows.add(
        LoadoutSlotRow(
          slot: GearSlot.values.byName(slotName),
          rating: rating,
          focus: StatFocus.values.byName(focusName),
          augmentKey: augmentKey,
          preferredProfile: PreferredProfile.values.byName(prefName),
          crystalKey: null,
        ),
      );
    }

    // Avoid name collisions under target character
    final existing = await repo.listLoadoutsForCharacter(targetCharacterId);
    final existingNames = existing.map((e) => e.name).toSet();

    var finalName = name;
    if (existingNames.contains(finalName)) {
      finalName = '$finalName (Imported)';
    }

    await repo.saveLoadout(
      LoadoutDraft(
        characterId: targetCharacterId,
        name: finalName,
        combatStyle: payload['combatStyle'] as String?,
        discipline: payload['discipline'] as String?,
        role: payload['role'] as String?,
        notes: payload['notes'] as String?,
        stimKey: stimKey,
        crystalMainKey: crystalMainKey,
        crystalOffKey: crystalOffKey,
        slotRows: slotRows,
      ),
    );
  }
}