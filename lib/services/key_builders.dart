import '../domain/slot_policy.dart';
import 'enums.dart';

enum PreferredProfile { AUTO, DPS, TANK }

/// Build a single gear key for a specific profile.
/// (You typically won't call this directly; you'll use candidates below.)
String buildGearKey({
  required int rating,
  required GearSlot slot,
  required GearProfile profile,
  required StatFocus focus,
}) {
  final slotKey = SlotPolicy.jsonSlotKey(slot);
  final norm = SlotPolicy.normalizeSelection(slot: slot, rating: rating, focus: focus);

  return 'GEAR_${norm.rating}_${slotKey}_${profile.name}_${norm.focus.name}';
}

/// Build the candidate keys to try for a slot selection.
/// By design: try DPS first, then TANK.
List<String> buildGearKeyCandidates({
  required int rating,
  required GearSlot slot,
  required StatFocus focus,
  PreferredProfile preferred = PreferredProfile.AUTO,
}) {
  final slotKey = SlotPolicy.jsonSlotKey(slot);
  final norm = SlotPolicy.normalizeSelection(slot: slot, rating: rating, focus: focus);

  final base = 'GEAR_${norm.rating}_${slotKey}_';

  List<String> order;
  switch (preferred) {
    case PreferredProfile.DPS:
      order = ['DPS', 'TANK'];
      break;
    case PreferredProfile.TANK:
      order = ['TANK', 'DPS'];
      break;
    case PreferredProfile.AUTO:
      order = ['DPS', 'TANK'];
      break;
  }

  return [
    '${base}${order[0]}_${norm.focus.name}',
    '${base}${order[1]}_${norm.focus.name}',
  ];
}