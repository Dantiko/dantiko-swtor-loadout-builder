import '../services/enums.dart';

class SlotPolicy {
  static bool isFocusless(GearSlot slot) {
    switch (slot) {
      case GearSlot.WRISTS:
      case GearSlot.WAIST:
        return true;
      default:
        return false;
    }
  }

  static String jsonSlotKey(GearSlot slot) {
    switch (slot) {
      case GearSlot.IMPLANT_1:
      case GearSlot.IMPLANT_2:
        return 'IMPLANT';
      case GearSlot.RELIC_1:
      case GearSlot.RELIC_2:
        return 'RELIC';
      default:
        return slot.name;
    }
  }

  static int clampRating(GearSlot slot, int rating) {
    if (slot == GearSlot.IMPLANT_1 || slot == GearSlot.IMPLANT_2) {
      if (rating > 340) return 340;
    }
    return rating;
  }

  static List<StatFocus> focusOptionsForSlot(GearSlot slot) {
    if (isFocusless(slot)) return const [StatFocus.NONE];

    if (slot == GearSlot.IMPLANT_1 || slot == GearSlot.IMPLANT_2) {
      return const [StatFocus.CRITICAL, StatFocus.ALACRITY, StatFocus.SHIELD, StatFocus.ABSORB];
    }

    if (slot == GearSlot.MAIN_HAND) return const [StatFocus.CRITICAL, StatFocus.SHIELD];
    if (slot == GearSlot.OFF_HAND) return const [StatFocus.ALACRITY, StatFocus.ABSORB];

    // Relics: allow NONE + SHIELD + ABSORB (lookup layer will decide which exists)
    if (slot == GearSlot.RELIC_1 || slot == GearSlot.RELIC_2) {
      return const [StatFocus.NONE, StatFocus.SHIELD, StatFocus.ABSORB];
    }

    return const [StatFocus.CRITICAL, StatFocus.ALACRITY, StatFocus.ACCURACY, StatFocus.SHIELD, StatFocus.ABSORB];
  }

  static bool showFocusDropdown(GearSlot slot) {
    final opts = focusOptionsForSlot(slot);
    return opts.length > 1;
  }

  static StatFocus normalizeFocus(GearSlot slot, StatFocus selected) {
  if (isFocusless(slot)) return StatFocus.NONE;

  if ((slot == GearSlot.IMPLANT_1 || slot == GearSlot.IMPLANT_2) && selected == StatFocus.ACCURACY) {
    return StatFocus.ALACRITY;
  }

  if (slot == GearSlot.MAIN_HAND && !(selected == StatFocus.CRITICAL || selected == StatFocus.SHIELD)) {
    return StatFocus.CRITICAL;
  }
  if (slot == GearSlot.OFF_HAND && !(selected == StatFocus.ALACRITY || selected == StatFocus.ABSORB)) {
    return StatFocus.ALACRITY;
  }

  if (slot == GearSlot.RELIC_1 || slot == GearSlot.RELIC_2) {
    if (selected == StatFocus.NONE || selected == StatFocus.SHIELD || selected == StatFocus.ABSORB) return selected;
    return StatFocus.NONE;
  }

  // Default slots: only allow the 5 real focuses (no NONE)
  switch (selected) {
    case StatFocus.CRITICAL:
    case StatFocus.ALACRITY:
    case StatFocus.ACCURACY:
    case StatFocus.SHIELD:
    case StatFocus.ABSORB:
      return selected;
    case StatFocus.NONE:
      return StatFocus.CRITICAL;
  }
}

  static ({int rating, StatFocus focus}) normalizeSelection({
    required GearSlot slot,
    required int rating,
    required StatFocus focus,
  }) {
    final r = clampRating(slot, rating);
    final f = normalizeFocus(slot, focus);
    return (rating: r, focus: f);
  }
}