import 'relic_effect.dart';

class RelicSelection {
  final String relicKey;
  final int rating;
  final RelicEffectType effectType;
  final bool effectActive;

  const RelicSelection({
    required this.relicKey,
    required this.rating,
    required this.effectType,
    this.effectActive = false,
  });

  RelicSelection copyWith({
    String? relicKey,
    int? rating,
    RelicEffectType? effectType,
    bool? effectActive,
  }) {
    return RelicSelection(
      relicKey: relicKey ?? this.relicKey,
      rating: rating ?? this.rating,
      effectType: effectType ?? this.effectType,
      effectActive: effectActive ?? this.effectActive,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'relicKey': relicKey,
      'rating': rating,
      'effectType': effectType.name,
      'effectActive': effectActive,
    };
  }

  factory RelicSelection.fromJson(Map<String, dynamic> json) {
    final effectName = json['effectType'] as String?;

    if (effectName == null) {
      throw const FormatException('Missing relic effect type');
    }
    final effectType = parseRelicEffect(effectName);

    return RelicSelection(
      relicKey: json['relicKey'] as String,
      rating: json['rating'] as int,
      effectType: effectType,
      effectActive: effectType.hasToggle
          ? json['effectActive'] == true
          : false,
    );
  }
}