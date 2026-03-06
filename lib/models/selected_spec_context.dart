enum CombatRole { DPS, HEALER, TANK }

class SelectedSpecContext {
  final String? combatStyle;     // e.g. "Juggernaut / Guardian"
  final String? discipline;      // e.g. "Vengeance / Vigilance"
  final CombatRole? role;        // optional for now, but very useful later

  const SelectedSpecContext({
    required this.combatStyle,
    required this.discipline,
    this.role,
  });

  bool get isSelected => combatStyle != null && discipline != null;
}

const double kBaseCritChanceBonus = 11.0;
const double kBaseAccuracyBonus = 101.0;
const double kBaseCritMultiplierBonus = 51.0;
const double kBaseDefenseBonus = 5.0;

bool isTankDiscipline(String? discipline) {
  final d = (discipline ?? '').toLowerCase();

  return 
      d.contains('darkness') ||
      d.contains('kinetic combat') ||
      d.contains('immortal') ||
      d.contains('defense') ||
      d.contains('shield tech') ||
      d.contains('shield specialist');
}

double alacrityBonusForDiscipline(String? discipline) {
  final d = (discipline ?? '').toLowerCase();

  // Carnage / Combat OR Arsenal / Gunnery gets +3%
  if (d.contains('carnage / combat')) return 3.0;
  if (d.contains('arsenal / gunnery')) return 3.0;
  // Lightning / Telekinetics gets +5%
  if (d.contains('lightning / telekinetics')) return 5.0;

  return 0.0;
}

double defenseBonusForDiscipline(String? discipline) {
  final d = (discipline ?? '').toLowerCase().trim();

  // Tank specs
  if (d.contains('darkness / kinetic combat')) return 11.0;
  if (d.contains('immortal / defense')) return 3.0;
  if (d.contains('shield tech / shield specialist')) return 4.0;

  // Remaining Assassin specs (Deception, Hatred) get +5%
  if (d.contains('deception / infiltration')) return 5.0;
  if (d.contains('hatred / serenity')) return 5.0;

  // Sorcerer specs (Lightning, Madness, Corruption) get +5%
  if (d.contains('lightning / telekinetics')) return 5.0;
  if (d.contains('madness / balance')) return 5.0;
  if (d.contains('corruption / seer')) return 5.0;

  // Powertech Advanced Prototype / Vanguard Tactics gets +3%
  if (d.contains('advanced prototype / tactics')) return 3.0;

  // Operative Concealment / Scoundrel Scrapper gets +2%
  if (d.contains('concealment / scrapper')) return 2.0;

  return 0.0;
}

double shieldBonusForDiscipline(String? discipline) {
  final d = (discipline ?? '').toLowerCase().trim();

  if (d.contains('darkness / kinetic combat')) return 15.0;
  if (d.contains('immortal / defense')) return 19.0;
  if (d.contains('shield tech / shield specialist')) return 17.0;

  return 0.0;
}

double absorbBonusForDiscipline(String? discipline) {
  final d = (discipline ?? '').toLowerCase().trim();

  if (d.contains('darkness / kinetic combat')) return 4.0;
  if (d.contains('shield tech / shield specialist')) return 4.0;

  return 0.0;
}