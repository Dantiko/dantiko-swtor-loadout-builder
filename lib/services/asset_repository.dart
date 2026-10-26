import 'dart:convert';
import 'package:flutter/services.dart';

import '../models/stat_bundle.dart';
import '../models/relic_bonuses.dart';

class AssetRepository {
  final Map<String, StatBundle> gear;
  final Map<String, StatBundle> augments;
  final Map<String, StatBundle> crystals;
  final Map<String, StatBundle> stims;
  final RelicBonusConfig relicBonuses;

  AssetRepository({
    required this.gear,
    required this.augments,
    required this.crystals,
    required this.stims,
    required this.relicBonuses,
  });

static Future<AssetRepository> load() async {
  Future<Map<String, StatBundle>> loadMap(String path) async {
    final raw = await rootBundle.loadString(path);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(
          k,
          StatBundle.fromJsonMap((v as Map).cast<String, dynamic>()),
        ));
  }

  final gear = await loadMap('assets/data/gear.json');
  final augments = await loadMap('assets/data/augments.json');
  final crystals = await loadMap('assets/data/crystals.json');
  final stims = await loadMap('assets/data/stims.json');
  final relicBonusJson = jsonDecode(
    await rootBundle.loadString('assets/data/relic_bonuses.json'),
  ) as Map<String, dynamic>;
  final relicBonuses = RelicBonusConfig.fromJson(relicBonusJson);

  // Inject safe "none" options
  augments.putIfAbsent('AUG_NONE', () => const StatBundle());
  crystals.putIfAbsent('CRYSTAL_NONE', () => const StatBundle());
  stims.putIfAbsent('STIM_NONE', () => const StatBundle());

  return AssetRepository(gear: gear, augments: augments, crystals: crystals, stims: stims, relicBonuses: relicBonuses);
}
}