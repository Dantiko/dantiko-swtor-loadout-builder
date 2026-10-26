import 'relic_effect.dart';
import 'stat_bundle.dart';

/// Loaded from assets/data/relic_bonuses.json by AssetRepository.
/// No bonus values are hardcoded in Dart.
class RelicBonusConfig {
  final Map<int, int> proc;
  final Map<int, int> activation;
  final Map<int, int> shieldAbsorbActivation;

  RelicBonusConfig._(this.proc, this.activation, this.shieldAbsorbActivation);

  factory RelicBonusConfig.fromJson(Map<String, dynamic> json) {
    final proc = <int, int>{};
    final activation = <int, int>{};
    final shieldAbsorb = <int, int>{};
    for (final entry in json.entries) {
      final rating = int.parse(entry.key);
      final values = (entry.value as Map).cast<String, dynamic>();
      proc[rating] = (values['proc'] as num).toInt();
      activation[rating] = (values['activation'] as num).toInt();
      shieldAbsorb[rating] = (values['shield_absorb_activation'] as num).toInt();
    }
    return RelicBonusConfig._(proc, activation, shieldAbsorb);
  }
}

/// Returns null for an unsupported rating (never silently grants zero).
StatBundle? relicActiveBonus(RelicBonusConfig config, RelicEffectType effect, int rating) {
  if (!effect.hasToggle) return const StatBundle();
  if (effect == RelicEffectType.shieldAbsorbActivation) {
    final value = config.shieldAbsorbActivation[rating];
    return value == null ? null : StatBundle(shield: value, absorb: value);
  }
  final value = (effect.isProc
      ? config.proc
      : config.activation)[rating];
  if (value == null) return null;
  return switch (effect) {
    RelicEffectType.masteryProc => StatBundle(mastery: value),
    RelicEffectType.powerProc || RelicEffectType.powerActivation =>
      StatBundle(power: value),
    RelicEffectType.criticalProc => StatBundle(critical: value),
    RelicEffectType.alacrityActivation => StatBundle(alacrity: value),
    RelicEffectType.defenseActivation => StatBundle(defense: value),
    RelicEffectType.shieldAbsorbActivation =>
      StatBundle(shield: value, absorb: value),
    RelicEffectType.absorbPassive || RelicEffectType.shieldPassive =>
      const StatBundle(),
  };
}
