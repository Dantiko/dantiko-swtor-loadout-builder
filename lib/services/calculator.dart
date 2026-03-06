import 'dart:math';
import '../domain/slot_policy.dart';
import '../domain/stat_caps.dart';
import '../domain/stat_formula_config.dart';
import '../models/selected_spec_context.dart';
import '../models/stat_bundle.dart';
import '../services/asset_repository.dart';
import '../services/enums.dart';
import '../services/key_builders.dart' show PreferredProfile, buildGearKey;

/// --- Primary stat rules (SWTOR) ---
/// We keep BOTH:
/// 1) An unrounded (double) mastery/endurance AFTER multipliers (used by later formulas)
/// 2) A rounded int mastery/endurance stored in totals for display
///
/// NOTE: You must set the correct base values for your target level.
/// Mastery uses the global primary multiplier (5%).
/// Endurance uses the global primary multiplier (5%) PLUS Assassin bonus (3%) = 8% total.
const double kPrimaryMultiplier = 1.05;

int _baseMastery(SelectedSpecContext specContext) => 1374;
int _baseEndurance(SelectedSpecContext specContext) => 1115; // per your note (adjust if needed)

double _enduranceMultiplier(SelectedSpecContext ctx) {
  final cs = (ctx.combatStyle ?? '').toLowerCase();
  final isAssassinOrShadow = cs.contains('assassin') || cs.contains('shadow');
  return isAssassinOrShadow ? 1.08 : 1.05;
}

/// Unrounded primaries (after multipliers) for downstream derived stat formulas.
class RawPrimaryStats {
  final double mastery;
  final double endurance;

  const RawPrimaryStats({
    required this.mastery,
    required this.endurance,
  });
}

double drCurvePercent({
  required double rating,         // the stat rating total (e.g. crit rating)
  required double level,          // level used in formula
  required double divisor,        // stat-specific divisor (patch-adjustable)
  required double capMultiplier,  // stat-specific cap multiplier (stable)
  double bonus = 0.0,             // additive bonus percent (e.g. +3%)
}) {
  if (rating <= 0) return bonus;

  final base = 1.0 - (1.0 / capMultiplier);
  final exponent = (rating / level) / divisor;

  final curved = capMultiplier * (1.0 - pow(base, exponent));
  return curved + bonus;
}

class DerivedStats {
  final int maxHealth;

  // Curve outputs (percentage points by default)
  final double accuracyPct;
  final double alacrityPct;
  final double critChancePct;
  final double critMultiplierPct;
  final double defenseChancePct;
  final double? shieldChancePct;
  final double? absorbPct;

  const DerivedStats({
    required this.maxHealth,
    required this.accuracyPct,
    required this.alacrityPct,
    required this.critChancePct,
    required this.critMultiplierPct,
    required this.defenseChancePct,
    required this.shieldChancePct,
    required this.absorbPct,
  });
}

/// ============================================================================
///  Inputs / Outputs
/// ============================================================================

class SlotSelection {
  final GearSlot slot;
  final int rating;
  final StatFocus focus;
  final String augmentKey;
  final PreferredProfile preferredProfile;

  const SlotSelection({
    required this.slot,
    required this.rating,
    required this.focus,
    required this.augmentKey,
    required this.preferredProfile,
  });
}

class GlobalSelection {
  final String stimKey;
  final String crystalMainKey;
  final String crystalOffKey;

  const GlobalSelection({
    required this.stimKey,
    required this.crystalMainKey,
    required this.crystalOffKey,
  });
}

class CalcResult {
  final StatBundle totals; // displayed totals (ints)
  final RawPrimaryStats raw; // unrounded primaries (doubles)
  final DerivedStats derived; // derived stats
  final List<String> warnings;

  const CalcResult({
    required this.totals,
    required this.raw,
    required this.derived,
    required this.warnings,
  });
}

/// ============================================================================
///  Internal helpers
/// ============================================================================

GearProfile _profileForSlotSelection(SlotSelection s) {
  // Wrists/Waist: user explicitly chooses DPS vs TANK variant
  if (s.slot == GearSlot.WRISTS || s.slot == GearSlot.WAIST) {
    return s.preferredProfile == PreferredProfile.TANK
        ? GearProfile.TANK
        : GearProfile.DPS;
  }

  // Everywhere else: infer profile from focus
  if (s.focus == StatFocus.SHIELD || s.focus == StatFocus.ABSORB) {
    return GearProfile.TANK;
  }

  return GearProfile.DPS;
}

StatBundle _add(StatBundle a, StatBundle b) => StatBundle(
      mastery: a.mastery + b.mastery,
      endurance: a.endurance + b.endurance,
      power: a.power + b.power,
      defense: a.defense + b.defense,
      critical: a.critical + b.critical,
      alacrity: a.alacrity + b.alacrity,
      accuracy: a.accuracy + b.accuracy,
      shield: a.shield + b.shield,
      absorb: a.absorb + b.absorb,
    );

DerivedStats _computeDerived({
  required StatBundle totals, // rounded totals
  required RawPrimaryStats raw, // unrounded primaries
  required SelectedSpecContext ctx,
  required StatFormulaConfig cfg,
  required bool hasShieldGenerator,
}) {
  final level = cfg.level.toDouble();

  // Bonuses (passives, buffs, etc.) can be added here later using ctx.

  final double accuracyBonus =
    kBaseAccuracyBonus + (isTankDiscipline(ctx.discipline) ? 10.0 : 0.0);

  final accuracyPct = drCurvePercent(
    rating: totals.accuracy.toDouble(),
    level: level,
    divisor: cfg.accuracyDiv,
    capMultiplier: StatCaps.accuracyCap,
    bonus: accuracyBonus,
  );

  final double alacrityBonus =
    alacrityBonusForDiscipline(ctx.discipline);

  final alacrityPct = drCurvePercent(
    rating: totals.alacrity.toDouble(),
    level: level,
    divisor: cfg.alacrityDiv,
    capMultiplier: StatCaps.alacrityCap,
    bonus: alacrityBonus,
  );

  final critFromCriticalPct = drCurvePercent(
  rating: totals.critical.toDouble(),
  level: level,
  divisor: cfg.critDiv,
  capMultiplier: StatCaps.criticalStatCap,
  bonus: 0.0,
  );

  // IMPORTANT: use unrounded mastery after primary multiplier
  final critFromMasteryPct = drCurvePercent(
    rating: raw.mastery,
    level: level,
    divisor: cfg.critFromMasteryDiv,
    capMultiplier: StatCaps.masteryToCritCap,
    bonus: 0.0,
  );

  final critChancePct = critFromCriticalPct + critFromMasteryPct + kBaseCritChanceBonus;

  final critMultiplierPct = drCurvePercent(
    rating: totals.critical.toDouble(),
    level: level,
    divisor: cfg.critDiv,
    capMultiplier: StatCaps.criticalStatCap,
    bonus: kBaseCritMultiplierBonus,
  );

  final double defenseBonus =
      kBaseDefenseBonus + defenseBonusForDiscipline(ctx.discipline);

  final defenseChancePct = drCurvePercent(
    rating: totals.defense.toDouble(),
    level: level,
    divisor: cfg.defenseDiv,
    capMultiplier: StatCaps.defenseCap,
    bonus: defenseBonus,
  );

  double? shieldChancePct;
  double? absorbPct;

  if (hasShieldGenerator) {
    final double shieldBonus =
      5.0 + shieldBonusForDiscipline(ctx.discipline);

    shieldChancePct = drCurvePercent(
      rating: totals.shield.toDouble(),
      level: level,
      divisor: cfg.shieldDiv,
      capMultiplier: StatCaps.shieldCap,
      bonus: shieldBonus,
      );

    final double absorbBonus = 20.0 + absorbBonusForDiscipline(ctx.discipline);

    absorbPct = drCurvePercent(
      rating: totals.absorb.toDouble(),
      level: level,
      divisor: cfg.absorbDiv,
      capMultiplier: StatCaps.absorbCap,
      bonus: absorbBonus,
    );
  } else {
    shieldChancePct = null;
    absorbPct = null;
  }

  // Max Health formula (your corrected version):
  // (1.01 * (105095 + round(unroundedEndurance * 14))).round()
  final maxHealth =
      (1.01 * (105095 + (raw.endurance * 14).round())).round();

  return DerivedStats(
    maxHealth: maxHealth,
    accuracyPct: accuracyPct,
    alacrityPct: alacrityPct,
    critChancePct: critChancePct,
    critMultiplierPct: critMultiplierPct,
    defenseChancePct: defenseChancePct,
    shieldChancePct: shieldChancePct,
    absorbPct: absorbPct,
  );
}

/// ============================================================================
///  Public API
/// ============================================================================

CalcResult computeTotals({
  required AssetRepository repo,
  required List<SlotSelection> slots,
  required GlobalSelection globals,
  required SelectedSpecContext specContext,
}) {
  final warnings = <String>[];
  var totals = const StatBundle();

  // ---- Gear + Augments ----
  for (final s in slots) {
    final norm = SlotPolicy.normalizeSelection(
      slot: s.slot,
      rating: s.rating,
      focus: s.focus,
    );

    final gearKey = buildGearKey(
      rating: norm.rating,
      slot: s.slot,
      profile: _profileForSlotSelection(s),
      focus: norm.focus,
    );

    final gearStats = repo.gear[gearKey];
    if (gearStats == null) {
      warnings.add('Missing gear key: $gearKey');
    } else {
      totals = _add(totals, gearStats);
    }

    if (s.augmentKey.isNotEmpty && s.augmentKey != 'AUG_NONE') {
      final augStats = repo.augments[s.augmentKey];
      if (augStats == null) {
        warnings.add('Missing augment key: ${s.augmentKey}');
      } else {
        totals = _add(totals, augStats);
      }
    }
  }

  // ---- Globals: Stim ----
  if (globals.stimKey.isNotEmpty && globals.stimKey != 'STIM_NONE') {
    final stimStats = repo.stims[globals.stimKey];
    if (stimStats == null) {
      warnings.add('Missing stim key: ${globals.stimKey}');
    } else {
      totals = _add(totals, stimStats);
    }
  }

  // ---- Globals: Crystals ----
  if (globals.crystalMainKey.isNotEmpty &&
      globals.crystalMainKey != 'CRYSTAL_NONE') {
    final c = repo.crystals[globals.crystalMainKey];
    if (c == null) {
      warnings.add('Missing crystal key: ${globals.crystalMainKey}');
    } else {
      totals = _add(totals, c);
    }
  }

  if (globals.crystalOffKey.isNotEmpty &&
      globals.crystalOffKey != 'CRYSTAL_NONE') {
    final c = repo.crystals[globals.crystalOffKey];
    if (c == null) {
      warnings.add('Missing crystal key: ${globals.crystalOffKey}');
    } else {
      totals = _add(totals, c);
    }
  }

  // ---- Primary totals: compute BOTH unrounded + displayed ----
  final baseM = _baseMastery(specContext);
  final baseE = _baseEndurance(specContext);

  final gearMastery = totals.mastery;
  final gearEndurance = totals.endurance;

  // Unrounded AFTER multiplier (used by later derived stats)
  final double unroundedMastery =
      (baseM + gearMastery) * kPrimaryMultiplier;
  final double unroundedEndurance =
      (baseE + gearEndurance) * _enduranceMultiplier(specContext);

  // Displayed totals (ints) — you said you switched to round.
  final int masteryFinal = unroundedMastery.round();
  final int enduranceFinal = unroundedEndurance.round();

  totals = StatBundle(
    mastery: masteryFinal,
    endurance: enduranceFinal,
    power: totals.power,
    defense: totals.defense,
    critical: totals.critical,
    alacrity: totals.alacrity,
    accuracy: totals.accuracy,
    shield: totals.shield,
    absorb: totals.absorb,
  );

  final raw = RawPrimaryStats(
    mastery: unroundedMastery,
    endurance: unroundedEndurance,
  );

  SlotSelection? offhandSelection;

  for (final s in slots) {
    if (s.slot == GearSlot.OFF_HAND) {
      offhandSelection = s;
      break;
    }
  }

  final bool hasShieldGenerator =
      offhandSelection != null &&
      offhandSelection.focus == StatFocus.ABSORB;

  final derived = _computeDerived(
    totals: totals,
    raw: raw,
    ctx: specContext,
    cfg: StatFormulaConfig.current,
    hasShieldGenerator: hasShieldGenerator,
  );

  // de-dupe warnings
  final deduped = <String>{};
  final cleanedWarnings = <String>[];
  for (final w in warnings) {
    if (deduped.add(w)) cleanedWarnings.add(w);
  }

  return CalcResult(
    totals: totals,
    raw: raw,
    derived: derived,
    warnings: cleanedWarnings,
  );
}