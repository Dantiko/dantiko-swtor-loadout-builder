class StatFormulaConfig {
  final int level;

  // divisors are patch-changeable
  final double critDiv;
  final double critFromMasteryDiv;
  final double alacrityDiv;
  final double accuracyDiv;
  final double defenseDiv;
  final double shieldDiv;
  final double absorbDiv;

  const StatFormulaConfig({
    required this.level,
    required this.critDiv,
    required this.critFromMasteryDiv,
    required this.alacrityDiv,
    required this.accuracyDiv,
    required this.defenseDiv,
    required this.shieldDiv,
    required this.absorbDiv,
  });

  // One place to update when SWTOR patches the math
  static const current = StatFormulaConfig(
    level: 80,
    critDiv: 2.41, 
    critFromMasteryDiv: 12.93,     
    alacrityDiv: 3.2,
    accuracyDiv: 3.2,
    defenseDiv: 5.0,
    shieldDiv: 2.079,
    absorbDiv: 2.189,
  );
}