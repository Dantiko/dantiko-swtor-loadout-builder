class StatBundle {
  final int mastery;
  final int endurance;
  final int power;
  final int defense;
  final int critical;
  final int alacrity;
  final int accuracy;
  final int shield;
  final int absorb;

  const StatBundle({
    this.mastery = 0,
    this.endurance = 0,
    this.power = 0,
    this.defense = 0,
    this.critical = 0,
    this.alacrity = 0,
    this.accuracy = 0,
    this.shield = 0,
    this.absorb = 0,
  });

  StatBundle operator +(StatBundle other) => StatBundle(
        mastery: mastery + other.mastery,
        endurance: endurance + other.endurance,
        power: power + other.power,
        defense: defense + other.defense,
        critical: critical + other.critical,
        alacrity: alacrity + other.alacrity,
        accuracy: accuracy + other.accuracy,
        shield: shield + other.shield,
        absorb: absorb + other.absorb,
      );

  static StatBundle fromJsonMap(Map<String, dynamic> m) => StatBundle(
        mastery: (m['mastery'] ?? 0) as int,
        endurance: (m['endurance'] ?? 0) as int,
        power: (m['power'] ?? 0) as int,
        defense: (m['defense'] ?? 0) as int,
        critical: (m['critical'] ?? 0) as int,
        alacrity: (m['alacrity'] ?? 0) as int,
        accuracy: (m['accuracy'] ?? 0) as int,
        shield: (m['shield'] ?? 0) as int,
        absorb: (m['absorb'] ?? 0) as int,
      );

  Map<String, int> asMap() => {
        'mastery': mastery,
        'endurance': endurance,
        'power': power,
        'defense': defense,
        'critical': critical,
        'alacrity': alacrity,
        'accuracy': accuracy,
        'shield': shield,
        'absorb': absorb,
      };
}