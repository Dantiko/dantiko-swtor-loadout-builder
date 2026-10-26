enum RelicEffectType {
  absorbPassive,
  shieldPassive,
  shieldAbsorbActivation,
  defenseActivation,
  powerActivation,
  alacrityActivation,
  masteryProc,
  powerProc,
  criticalProc,
}

extension RelicEffectTypeExtension on RelicEffectType {
  String get displayName => switch (this) {
    RelicEffectType.absorbPassive => 'Relic of Avoidance',
    RelicEffectType.shieldPassive => 'Relic of the Shield Matrix',
    RelicEffectType.shieldAbsorbActivation => 'Relic of the Shrouded Crusader',
    RelicEffectType.defenseActivation => 'Relic of Imperiling Serenity',
    RelicEffectType.powerActivation => 'Relic of Boundless Ages',
    RelicEffectType.alacrityActivation => 'Relic of the Primeval Fatesealer',
    RelicEffectType.masteryProc => 'Relic of Focused Retribution',
    RelicEffectType.powerProc => 'Relic of Serendipitous Assault',
    RelicEffectType.criticalProc => 'Relic of Devastating Vengeance',
  };

  bool get hasToggle => this != RelicEffectType.absorbPassive &&
      this != RelicEffectType.shieldPassive;
  bool get isProc => this == RelicEffectType.masteryProc ||
      this == RelicEffectType.powerProc || this == RelicEffectType.criticalProc;
  bool get isTankPassive => !hasToggle;
}

RelicEffectType parseRelicEffect(String value) {
  for (final effect in RelicEffectType.values) {
    if (effect.name == value) return effect;
  }
  throw FormatException('Unknown relic effect type: $value');
}

RelicEffectType? legacyRelicForFocus(String focus) => switch (focus) {
  'SHIELD' => RelicEffectType.shieldPassive,
  'ABSORB' => RelicEffectType.absorbPassive,
  _ => null, // Old DPS relics did not identify which specific relic was used.
};
