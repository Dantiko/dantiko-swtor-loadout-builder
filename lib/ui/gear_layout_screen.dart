import 'package:flutter/material.dart';
import '../domain/slot_policy.dart';
import '../models/stat_bundle.dart';
import '../services/asset_repository.dart';
import '../services/calculator.dart';
import '../services/enums.dart';
import '../services/key_builders.dart' show PreferredProfile, buildGearKey;
import '../models/selected_spec_context.dart';
import '../data/loadout_repository.dart';
import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_checker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../data/loadout_transfer.dart';

// Turn on only while tuning anchors
const bool kAnchorDebug = false;

class GearLayoutScreen extends StatefulWidget {
  final AssetRepository repo;
  const GearLayoutScreen({super.key, required this.repo});

  @override
  State<GearLayoutScreen> createState() => _GearLayoutScreenState();
}

class _GearLayoutScreenState extends State<GearLayoutScreen> {
  // Globals (still used for totals, but no longer edited via "Globals" sheet)
  String? selectedClass;
  String? selectedDiscipline;
  String stimKey = 'STIM_NONE';
  String crystalMainKey = 'CRYSTAL_NONE';
  String crystalOffKey = 'CRYSTAL_NONE';

  late final Map<GearSlot, _SlotState> slotState;

  // Background image aspect ratio: 303x578
  static const double _paperDollAspect = 303 / 578;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });

    // Defensive: ensure NONE keys exist
    widget.repo.augments.putIfAbsent('AUG_NONE', () => const StatBundle());
    widget.repo.stims.putIfAbsent('STIM_NONE', () => const StatBundle());
    widget.repo.crystals.putIfAbsent('CRYSTAL_NONE', () => const StatBundle());

    slotState = {for (final s in _slotOrder) s: _SlotState.initialForSlot(s)};
    for (final e in slotState.entries) {
      e.value.normalize(e.key);
    }
  }

  final LoadoutRepository _loadoutRepo = LoadoutRepository();

  final GlobalKey<ScaffoldMessengerState> _totalsPaneMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

  void _showTotalsPaneSnackBar(String message) {
    _totalsPaneMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  CalcResult _calc() {
    final slots = <SlotSelection>[];

    for (final entry in slotState.entries) {
      final slot = entry.key;
      final st = entry.value;

      st.normalize(slot);

      if (st.rating == null) continue;

      final norm = SlotPolicy.normalizeSelection(
        slot: slot,
        rating: st.rating!,
        focus: st.focus,
      );

      slots.add(SlotSelection(
        slot: slot,
        rating: norm.rating,
        focus: norm.focus,
        augmentKey: st.augmentKey,
        preferredProfile: st.preferredProfile,
      ));
    }

    final globals = GlobalSelection(
      stimKey: stimKey,
      crystalMainKey: crystalMainKey,
      crystalOffKey: crystalOffKey,
    );

    final ctx = SelectedSpecContext(
      combatStyle: selectedClass,
      discipline: selectedDiscipline,
      // role: _inferRole(selectedDiscipline), // optional
    );

    return computeTotals(
      repo: widget.repo,
      slots: slots,
      globals: globals,
      specContext: ctx,
    );
  }

  @override
  Widget build(BuildContext context) {
    final res = _calc();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 820;

        if (isWide) {
          return Row(
            children: [
              SizedBox(width: 220, child: _classSpecPane()),
              SizedBox(width: 380, child: _paperDollPane()),
              Expanded(child: _totalsPane(res)),
            ],
          );
        }

        return ListView(
          children: [
            SizedBox(width: 220, child: _classSpecPane()),
            SizedBox(height: 720, child: _paperDollPane()),
            SizedBox(height: 520, child: _totalsPane(res)),
          ],
        );
      },
    );
  }

  // Helper: only WRISTS/WAIST use the DPS vs TANK variant.
  // Everything else defaults to DPS since you removed the old “profile” selection.
  GearProfile _profileForSlot(GearSlot slot, _SlotState st) {
    // Wrists/Waist: explicit DPS/TANK variant selection
    if (slot == GearSlot.WRISTS || slot == GearSlot.WAIST) {
      return st.preferredProfile == PreferredProfile.TANK
          ? GearProfile.TANK
          : GearProfile.DPS;
    }

    // Everywhere else: infer profile from focus
    // (Shield/Absorb items live under TANK profile in your gear.json)
    if (st.focus == StatFocus.SHIELD || st.focus == StatFocus.ABSORB) {
      return GearProfile.TANK;
    }

    return GearProfile.DPS;
  }

  Widget _classSpecPane() {
    final disciplines = (selectedClass == null)
        ? const <String>[]
        : (_disciplineMap[selectedClass!] ?? const <String>[]);

    return Material(
      type: MaterialType.transparency,
      child: _StatsBackgroundFrame(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Reset class/spec button (you wanted it similar to clear)
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SwtorPillButton(
                    label: 'Reset Class/Spec',
                    onTap: _confirmResetClassSpec,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              DropdownButton<String>(
                value: selectedClass,
                isExpanded: true,
                icon: const SizedBox.shrink(),
                dropdownColor: Colors.black87,
                hint: const Text(
                  'Select Class',
                  style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500,),
                ),

                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),

                underline: Container(
                  height: 1,
                  color: Colors.white70,
                ),

                items: _classList.map((c) {
                  return DropdownMenuItem<String>(
                    value: c,
                    child: Text(
                      c,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  );
                }).toList(),

                onChanged: (v) {
                  setState(() {
                    selectedClass = v;
                    selectedDiscipline = null;
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButton<String>(
                value: selectedDiscipline,
                isExpanded: true,
                icon: const SizedBox.shrink(),
                dropdownColor: Colors.black87,

                hint: const Text(
                  'Select Discipline',
                  style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                ),

                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),

                underline: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    height: 1,
                    color: Colors.white70,
                  ),
                ),

                items: disciplines.map((d) {
                  return DropdownMenuItem<String>(
                    value: d,
                    child: Text(
                      d,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  );
                }).toList(),

                onChanged: (v) {
                  setState(() {
                    selectedDiscipline = v;
                  });
                },
              ),

              const SizedBox(height: 10),

              // Save/Load buttons (no Export here anymore)
              SwtorPillBar(
                actions: [
                  SwtorPillAction(label: 'Save Loadout', onTap: (selectedClass == null || selectedDiscipline == null)
                        ? null
                        : _openSaveLoadoutDialog,),
                  SwtorPillAction(label: 'Load Loadout', onTap: _openLoadLoadoutDialog),
                  SwtorPillAction(label: 'Clear Loadout', onTap: _confirmClearLoadout),
                ],
              ),

              const Spacer(),

              Align(
                alignment: Alignment.bottomLeft,
                child: SwtorPillButton(
                  label: 'Check for Updates',
                  onTap: () => _checkForUpdates(manual: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  final List<String> _classList = [
    'Juggernaut / Guardian',
    'Marauder / Sentinel',
    'Sorcerer / Sage',
    'Assassin / Shadow',
    'Powertech / Vanguard',
    'Mercenary / Commando',
    'Operative / Scoundrel',
    'Sniper / Gunslinger',
  ];

  final Map<String, List<String>> _disciplineMap = {
    'Juggernaut / Guardian': ['Vengeance / Vigilance', 'Rage / Focus', 'Immortal / Defense'],
    'Marauder / Sentinel': ['Annihilation / Watchman', 'Carnage / Combat', 'Fury / Concentration'],
    'Sorcerer / Sage': ['Lightning / Telekinetics', 'Madness / Balance', 'Corruption / Seer'],
    'Assassin / Shadow': ['Deception / Infiltration', 'Hatred / Serenity', 'Darkness / Kinetic Combat'],
    'Powertech / Vanguard': ['Pyrotech / Plasmatech', 'Advanced Prototype / Tactics', 'Shield Tech / Shield Specialist'],
    'Mercenary / Commando': ['Arsenal / Gunnery', 'Innovative Ordnance / Assault Specialist', 'Bodyguard / Combat Medic'],
    'Operative / Scoundrel': ['Concealment / Scrapper', 'Lethality / Ruffian', 'Medicine / Sawbones'],
    'Sniper / Gunslinger': ['Marksmanship / Sharpshooter', 'Engineering / Saboteur', 'Virulence / Dirty Fighting'],
  };

  Widget _paperDollPane() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: AspectRatio(
          aspectRatio: _paperDollAspect, // 303 / 578
          child: _BackgroundFrame(
            child: LayoutBuilder(
              builder: (context, c) {
                final W = c.maxWidth;
                final H = c.maxHeight;

                return Stack(
                  children: [
                    // Gear slot hitboxes (border = focus color, fill = secondary stat color)
                    for (final entry in _slotAnchors.entries) ...[
                      () {
                        final slot = entry.key;
                        final anchor = entry.value;
                        final st = slotState[slot]!;
                        final isSelected = st.rating != null;

                        // Unselected defaults
                        Color borderColor = Colors.white.withValues(alpha: 0.80);
                        Color fillColor = Colors.transparent;

                        if (isSelected) {
                          // Build the same gear key your calculator uses
                          final gearKey = buildGearKey(
                            rating: st.rating!,
                            slot: slot,
                            profile: _profileForSlot(slot, st),
                            focus: st.focus,
                          );

                            final stats = widget.repo.gear[gearKey];

                            // Inlay: focus color (transparent for NONE)
                            fillColor = _focusBorderColor(st.focus).withValues(alpha: 0.40);

                            // Border: power/defense cue from stats
                            borderColor = stats == null ? Colors.white : _secondaryFillColorFromStats(stats);

                            // If you want “NONE focus” to have no inlay at all:
                            if (st.focus == StatFocus.NONE) {
                              fillColor = Colors.transparent;
                            }

                            // Optional: if stats is null, keep the default white border
                            if (stats == null) {
                              borderColor = Colors.white;
                            }
                        }

                        return Positioned(
                          left: W * anchor.x,
                          top: H * anchor.y,
                          width: W * anchor.w,
                          height: H * anchor.h,
                          child: Stack(
                            children: [
                              _SlotHitbox(
                                key: ValueKey(slot),
                                borderColor: borderColor,
                                fillColor: fillColor,
                                isSelected: isSelected,
                                onTap: () => _openSlotSheet(slot),
                              ),

                              // Rating text overlay (gear rating + (augment rating))
                              Positioned(
                                left: 4,
                                bottom: 4,
                                child: _ratingOverlayText(
                                  gearRating: st.rating,
                                  augmentRating: _augmentRatingFromKey(st.augmentKey),
                                ),
                              ),

                              // Crystal indicator (top-left) — only for Main Hand / Off Hand
                              () {
                                if (!isSelected) return const SizedBox.shrink();

                                final isMain = slot == GearSlot.MAIN_HAND;
                                final isOff = slot == GearSlot.OFF_HAND;
                                if (!isMain && !isOff) return const SizedBox.shrink();

                                final crystalKey = isMain ? crystalMainKey : crystalOffKey;
                                if (crystalKey == 'CRYSTAL_NONE') return const SizedBox.shrink();

                                final crystalStats = widget.repo.crystals[crystalKey];
                                if (crystalStats == null) return const SizedBox.shrink();

                                final c = _crystalIndicatorColor(crystalStats);
                                if (c == Colors.transparent) return const SizedBox.shrink();

                                return _CornerIndicatorBox(
                                  color: c,
                                  alignment: Alignment.topLeft,
                                );
                              }(),

                              // Augment indicator (bottom-right)
                              () {
                                if (!isSelected) return const SizedBox.shrink();
                                if (st.augmentKey == 'AUG_NONE') return const SizedBox.shrink();

                                final augStats = widget.repo.augments[st.augmentKey];
                                if (augStats == null) return const SizedBox.shrink();

                                final c = _augmentIndicatorColor(augStats);
                                return _AugmentCornerDot(color: c);
                              }(),
                            ],
                          ),
                        );
                      }(),
                    ],

                      // Stim hitbox (bottom-left accessory square)
                    () {
                      final stimSelected = stimKey != 'STIM_NONE';
                      final stimStats =
                          stimSelected ? widget.repo.stims[stimKey] : null;

                      // Default unselected look
                      Color stimBorderColor = Colors.white.withValues(alpha: 0.6);
                      Color stimFillColor = Colors.transparent;

                      // Selected look (inlay = primary, border = secondary)
                      if (stimStats != null) {
                        stimFillColor =
                            _primaryStatColorFromStim(stimStats).withValues(alpha: 0.40);
                        stimBorderColor = _secondaryStatColorFromStim(stimStats);
                      }

                      return Positioned(
                        left: W * _stimAnchor.x,
                        top: H * _stimAnchor.y,
                        width: W * _stimAnchor.w,
                        height: H * _stimAnchor.h,
                        child: Stack(
                          children: [
                            _SlotHitbox(
                              borderColor: stimBorderColor,
                              fillColor: stimFillColor,
                              isSelected: stimSelected,
                              onTap: _openStimSheet,
                            ),
                            Center(
                              child: Text(
                                'Stim',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.95),
                                  shadows: const [Shadow(blurRadius: 4)],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }(),

                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SwtorPillButton(
                          label: 'Clear Gear Selections',
                          onTap: _confirmClearAll,
                        ),
                      ),
                    ),

                    if (kAnchorDebug) const Positioned.fill(child: _AnchorDebugOverlay()),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _totalsPane(CalcResult res) {
    final StatBundle totals = res.totals;

    const orderedKeys = <String>[
      'mastery',
      'endurance',
      'power',
      'critical',
      'alacrity',
      'accuracy',
      'defense',
      'absorb',
      'shield',
    ];

    final displayKeys = <String>[...orderedKeys];


    return ScaffoldMessenger(
      key: _totalsPaneMessengerKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _StatsBackgroundFrame(
          child: LayoutBuilder(
            builder: (context, box) {
              // Pick a "design height" that represents when the pane looks perfect.
              // Tune this once based on your preferred window size.
              const designHeight = 700.0;

              // Scale down only when space is tight; never scale up.
              final scale = (box.maxHeight / designHeight).clamp(0.72, 1.0);

              double s(double v) => v * scale;

              final headerStyle = Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Colors.white, fontSize: (Theme.of(context).textTheme.headlineSmall?.fontSize ?? 24) * scale);

              return DefaultTextStyle(
                style: TextStyle(color: Colors.white, fontSize: 14 * scale),
                child: IconTheme(
                  data: IconThemeData(color: Colors.white, size: 24 * scale),
                  child: ListTileTheme(
                    textColor: Colors.white,
                    iconColor: Colors.white,
                    child: Padding(
                      padding: EdgeInsets.all(s(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Totals',
                                  style: headerStyle,
                                ),
                              ),
                              InkWell(
                                onTap: _showTotalsNotes,
                                child: Text(
                                  '| Click for Totals Notes |',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: Colors.white70,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: s(10)),

                          // Totals: NON-scrollable
                          Column(
                            children: [
                              for (final key in displayKeys)
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: s(5)),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 7,
                                        child: Text(
                                          '${_prettyStatName(key)}:',
                                          style: TextStyle(
                                            color: _statLabelColor(key),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14 * scale,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          _getStatValue(totals, key).toString(),
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14 * scale,
                                          ),
                                        ),
                                      ),
                                      const Expanded(flex: 4, child: SizedBox()),
                                    ],
                                  ),
                                ),
                            ],
                          ),

                          // Move divider down slightly (scaled)
                          SizedBox(height: s(16)),
                          Divider(color: Colors.white.withValues(alpha: 0.25), height: 1),
                          SizedBox(height: s(10)),

                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Details',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(color: Colors.white),
                                ),
                              ),

                              // Clickable text label instead of icon
                              InkWell(
                                onTap: _showDetailsNote,
                                child: Text(
                                  '| Click for Percentage Notes |',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: Colors.white70,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: s(8)),

                          // Details: NON-scrollable (make sure _detailsPane doesn't contain scroll)
                          // If details content grows later, it will scale down with the same factor.
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(top: s(2)),
                              child: _detailsPaneScaled(res, scale),
                            ),
                          ),

                          if (res.warnings.isNotEmpty) ...[
                            SizedBox(height: s(8)),
                            Text(
                              'Warnings',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: Colors.white, fontSize: (Theme.of(context).textTheme.titleMedium?.fontSize ?? 16) * scale),
                            ),
                            SizedBox(height: s(6)),
                            ...res.warnings.take(3).map(
                                  (w) => Text(
                                    '• $w',
                                    style: TextStyle(color: Colors.white70, fontSize: 12 * scale),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// A scaled wrapper so Details inherits the same scaling.
  /// (This avoids using FittedBox/Transform.)
  Widget _detailsPaneScaled(CalcResult res, double scale) {
    return DefaultTextStyle.merge(
      style: TextStyle(fontSize: 14 * scale),
      child: _detailsPane(res),
    );
  }

  Widget _detailsPane(CalcResult res) {
    final d = res.derived;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailRow(label: 'Accuracy', value: _fmtPct(d.accuracyPct)),
        _detailRow(label: 'Alacrity', value: _fmtPct(d.alacrityPct)),
        _detailRow(label: 'Critical Chance', value: _fmtPct(d.critChancePct)),
        _detailRow(label: 'Critical Multiplier', value: _fmtPct(d.critMultiplierPct)),
        _detailRow(label: 'Max Health', value: d.maxHealth.toString()),
        _detailRow(label: 'Defense Chance', value: _fmtPct(d.defenseChancePct)),
        _detailRow(label: 'Shield Chance', value: _fmtPct(res.derived.shieldChancePct)),
        _detailRow(label: 'Shield Absorb', value: _fmtPct(res.derived.absorbPct)),
      ],
    );
  }

  Widget _detailRow({
    required String label,
    required String value,
    }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 7,
            child: Text(
              '$label:',
              style: const TextStyle(color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right, // ✅ true right alignment
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const Expanded(
            flex: 4,
            child: SizedBox(),
          ),
        ],
      ),
    );
  }

  void _showTotalsNotes() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Totals Notes'),
        content: const Text(
          'Stat Totals shown are calculated assuming level 80, all Datacrons are obtained, '
          'all Class Buffs are obtained,'
          'NO Relic Procs/Activations, and NO Guild Buffs',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showDetailsNote() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('NOTE:'),
        content: const SingleChildScrollView(
          child: Text(
            'Stat Percentages are calculated assuming level 80, Companion Buffs and Class Buffs exist, but NOT any Guild Buffs.\n\n'
            'Alacrity percentage is calculated assuming base percentage WITHOUT activating abilities that buff Alacrity (e.g. Berserk/Zen on Carnage/Combat and Polarity Shift/Mental Alacrity on Sorcerer/Sage) but DOES take into account bonus base percentages (e.g. Ataru Form or Focal Lightning/Telekinetic Focal Point).\n\n'
            'Defense percentage is calculated WITHOUT taking into account optional Skill Tree buffs OR any ability that increases Defense Chance.\n\n'
            'Shield/Absorb percentages are calculated WITHOUT taking into account abilities/combat passives that buff those stats (e.g. Dark Ward/Kinetic Ward, Aegis Assault/Warding Strike, Shield Enhancers).',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openSlotSheet(GearSlot slot) {
    final st = slotState[slot]!;
    final repo = widget.repo;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final ratingOptions = <int?>[null, ..._ratingOptionsForSlot(slot)];
            final focusOptions = SlotPolicy.focusOptionsForSlot(slot);

            final showVariant = st.rating != null && _slotUsesVariantToggle(slot);
            final showFocus = st.rating != null &&
                !_slotUsesVariantToggle(slot) &&
                SlotPolicy.showFocusDropdown(slot);

            final augmentKeys = _sortedKeys(repo.augments.keys);

            final crystalKeys = _sortedKeys(repo.crystals.keys);
            final isMain = slot == GearSlot.MAIN_HAND;
            final isOff = slot == GearSlot.OFF_HAND;
            final showCrystal = (isMain || isOff) && st.rating != null;

            void apply(void Function() fn) {
              fn();
              st.normalize(slot);

              // If weapon is set to None, clear its crystal too.
              if (st.rating == null) {
                if (isMain) crystalMainKey = 'CRYSTAL_NONE';
                if (isOff) crystalOffKey = 'CRYSTAL_NONE';
              }

              setModalState(() {});
              setState(() {});
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                top: 6,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 14,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_gearSlotLabel(slot), style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 10),

                  _DropdownRowNullable<int>(
                    label: 'Item Rating',
                    value: st.rating,
                    items: ratingOptions,
                    onChanged: (v) => apply(() => st.rating = v),
                    display: (v) => v == null ? 'None' : v.toString(),
                  ),
                  const SizedBox(height: 10),

                  if (showVariant) ...[
                    _DropdownRow<PreferredProfile>(
                      label: 'DPS / Tank',
                      value: st.preferredProfile,
                      items: const [
                        PreferredProfile.DPS,
                        PreferredProfile.TANK,
                      ],
                      onChanged: (v) => apply(() => st.preferredProfile = v),
                      display: _preferredProfileLabel,
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (showFocus) ...[
                    _DropdownRow<StatFocus>(
                      label: 'Tertiary Stat',
                      value: st.focus,
                      items: focusOptions,
                      onChanged: (v) => apply(() => st.focus = v),
                      display: _focusLabel,
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Crystal selection for weapons (above augments)
                  if (showCrystal) ...[
                    _DropdownRow<String>(
                      label: isMain ? 'Crystal (Mainhand)' : 'Crystal (Offhand)',
                      value: isMain ? crystalMainKey : crystalOffKey,
                      items: crystalKeys,
                      onChanged: (v) => apply(() {
                        if (isMain) crystalMainKey = v;
                        if (isOff) crystalOffKey = v;
                      }),
                      display: _friendlyKeyLabel,
                      enabled: st.rating != null,
                    ),
                    const SizedBox(height: 10),
                  ],

                  _DropdownRow<String>(
                    label: 'Augment',
                    value: st.augmentKey,
                    items: augmentKeys,
                    onChanged: (v) => apply(() => st.augmentKey = v),
                    display: _friendlyKeyLabel,
                    enabled: st.rating != null,
                  ),

                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openStimSheet() {
    final repo = widget.repo;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final stimKeys = _sortedKeys(repo.stims.keys);

            void apply(void Function() fn) {
              fn();
              setModalState(() {});
              setState(() {});
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                top: 6,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 14,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Stim', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  _DropdownRow<String>(
                    label: 'Stim',
                    value: stimKey,
                    items: stimKeys,
                    onChanged: (v) => apply(() => stimKey = v),
                    display: _friendlyKeyLabel,
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

    void _clearAllSelections() {
    setState(() {
      // Clear all gear slots
      for (final slot in slotState.keys) {
        slotState[slot] = _SlotState.initialForSlot(slot);
        slotState[slot]!.normalize(slot);
      }

      // Clear stim + crystals
      stimKey = 'STIM_NONE';
      crystalMainKey = 'CRYSTAL_NONE';
      crystalOffKey = 'CRYSTAL_NONE';
    });
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all selections?'),
        content: const Text('This will remove all Gear, Augment, Crystal, and Stim selections.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (ok == true) {
      _clearAllSelections();
    }
  }

  Future<void> _confirmResetClassSpec() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Class/Spec?'),
        content: const Text('Clear the selected Class and Discipline?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      selectedClass = null;
      selectedDiscipline = null;
    });
  }

  Future<void> _confirmClearLoadout() async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Clear Loadout?'),
      content: const Text('Clear Class/Discipline AND all Gear/Augment/Stim/Crystals selections?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Clear'),
        ),
      ],
    ),
  );

  if (ok != true) return;

    setState(() {
      // class/spec
      selectedClass = null;
      selectedDiscipline = null;

      // globals
      stimKey = 'STIM_NONE';
      crystalMainKey = 'CRYSTAL_NONE';
      crystalOffKey = 'CRYSTAL_NONE';

      // slots
      for (final slot in slotState.keys) {
        slotState[slot] = _SlotState.initialForSlot(slot);
      }
    });
  }

  List<LoadoutSlotRow> _buildSlotRowsFromState() {
    final rows = <LoadoutSlotRow>[];

    for (final entry in slotState.entries) {
      final slot = entry.key;
      final st = entry.value;

      rows.add(
        LoadoutSlotRow(
          slot: slot,
          rating: st.rating ?? 0, // 0 means NONE
          focus: st.rating == null ? StatFocus.NONE : st.focus,
          augmentKey: st.rating == null ? 'AUG_NONE' : st.augmentKey,
          preferredProfile: st.rating == null
              ? (_SlotState.initialForSlot(slot).preferredProfile)
              : st.preferredProfile,
          crystalKey: null, // crystals are globals in your design
        ),
      );
    }

    return rows;
  }

  void _applyLoadout(LoadoutFull full) {
    setState(() {
      selectedClass = full.meta.combatStyle;
      selectedDiscipline = full.meta.discipline;

      stimKey = full.globals.stimKey;
      crystalMainKey = full.globals.crystalMainKey;
      crystalOffKey = full.globals.crystalOffKey;

      // Reset everything to initial first (prevents leftover selections)
      for (final slot in slotState.keys) {
        slotState[slot] = _SlotState.initialForSlot(slot);
      }

      // Apply saved slot rows
      for (final e in full.slots.entries) {
        final slot = e.key;
        final saved = e.value;

        final st = slotState[slot];
        if (st == null) continue;

        // 0 means NONE
        if (saved.rating <= 0) {
          slotState[slot] = _SlotState.initialForSlot(slot);
          continue;
        }

        st.rating = saved.rating;
        st.focus = saved.focus;
        st.augmentKey = saved.augmentKey;
        st.preferredProfile = saved.preferredProfile;

        // Ensure constraints are enforced
        st.normalize(slot);
      }
    });
  }

  Future<int?> _createCharacterDialog() async {
    final nameCtrl = TextEditingController();

    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Character'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Character name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              final id = await _loadoutRepo.createCharacter(
                name: name,
                combatStyle: selectedClass,
                discipline: selectedDiscipline,
              );

              if (!ctx.mounted) return;
              Navigator.of(ctx).pop(id);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSaveLoadoutDialog() async {
    var characters = (await _loadoutRepo.listCharacters()).toList(); // growable
    if (!mounted) return;

    int? selectedCharacterId = characters.isNotEmpty ? characters.first.id : null;

    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    String characterNameFor(int? id) {
      if (id == null) return '';
      final match = characters.where((c) => c.id == id);
      if (match.isEmpty) return '';
      return match.first.name;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Save Loadout'),
              content: SizedBox(
                width: 620,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Character dropdown + create
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedCharacterId,
                            isExpanded: true,
                            icon: const SizedBox.shrink(),
                            decoration: const InputDecoration(labelText: 'Character'),
                            items: [
                              for (final c in characters)
                                DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                            ],
                            onChanged: (v) => setLocal(() => selectedCharacterId = v),
                          ),
                        ),
                        const SizedBox(width: 10),

                        OutlinedButton(
                          onPressed: () async {
                            final id = await _createCharacterDialog();
                            if (id == null) return;

                            final updated = await _loadoutRepo.listCharacters();
                            if (!mounted) return;

                            setLocal(() {
                              characters = updated.toList(); // replace list (growable)
                              selectedCharacterId = id;
                            });
                          },
                          child: const Text('New Character'),
                        ),

                        const SizedBox(width: 8),

                        // ✅ Manage characters
                        OutlinedButton(
                          onPressed: () async {
                            await _openManageCharactersDialog();

                            final updated = await _loadoutRepo.listCharacters();
                            if (!mounted) return;

                            setLocal(() {
                              characters = updated.toList();
                              if (selectedCharacterId != null &&
                                  !characters.any((c) => c.id == selectedCharacterId)) {
                                selectedCharacterId = characters.isNotEmpty ? characters.first.id : null;
                              }
                            });
                          },
                          child: const Text('Manage Characters'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Loadout Name',
                        hintText: 'e.g. 344 DPS Build',
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notes (Optional)',
                      ),
                      onChanged: (_) => setLocal(() {}),
                    ),

                    const SizedBox(height: 12),

                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: nameCtrl,
                      builder: (_, _, _) { 
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.05), // subtle light panel on dark bg
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.12),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Saved as:',
                                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),

                              Text(
                                '(${characterNameFor(selectedCharacterId)}) ${nameCtrl.text.trim()}',
                                style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),

                              const SizedBox(height: 2),

                              Text(
                                [
                                  if ((selectedClass ?? '').isNotEmpty) selectedClass!,
                                  if ((selectedDiscipline ?? '').isNotEmpty) selectedDiscipline!,
                                ].join(' • '),
                                style: Theme.of(ctx).textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),

                              if (notesCtrl.text.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  notesCtrl.text.trim(),
                                  style: Theme.of(ctx).textTheme.bodySmall,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final charId = selectedCharacterId;
                    final name = nameCtrl.text.trim();

                    if (charId == null) return; // requires a character
                    if (name.isEmpty) return;

                    final draft = LoadoutDraft(
                      characterId: charId,
                      name: name,
                      combatStyle: selectedClass,
                      discipline: selectedDiscipline,
                      role: null, // optional: derive later if you want
                      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                      stimKey: stimKey,
                      crystalMainKey: crystalMainKey,
                      crystalOffKey: crystalOffKey,
                      slotRows: _buildSlotRowsFromState(),
                    );

                    await _loadoutRepo.saveLoadout(draft);

                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openLoadLoadoutDialog() async {
    // Pull characters once up front; we’ll refresh inside the dialog when needed.
    var characters = (await _loadoutRepo.listCharacters()).toList();
    if (!mounted) return;

    // Filters
    int? characterFilterId; // null = All
    String? disciplineFilter; // null = All
    final queryCtrl = TextEditingController();

    // Results shown + a separate list used ONLY to populate discipline dropdown
    List<LoadoutSummary> results = await _loadoutRepo.searchLoadouts(limit: 200);
    List<LoadoutSummary> allForDisciplineOptions = results;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            // Layout constants (must not be const here)
            final double labelWidth = 130;

            // Refresh helper: keeps discipline dropdown populated from an UNFILTERED discipline list
            Future<void> refresh() async {
              final q = queryCtrl.text.trim();

              // Unfiltered (discipline = null) list solely for dropdown options
              allForDisciplineOptions = await _loadoutRepo.searchLoadouts(
                characterId: characterFilterId,
                query: q.isEmpty ? null : q,
                discipline: null,
                limit: 500,
              );

              // Actual visible results (discipline filtered)
              results = await _loadoutRepo.searchLoadouts(
                characterId: characterFilterId,
                query: q.isEmpty ? null : q,
                discipline: (disciplineFilter == null || disciplineFilter!.trim().isEmpty)
                    ? null
                    : disciplineFilter,
                limit: 500,
              );

              if (!mounted) return;
              setLocal(() {});
            }

            String characterNameFor(int characterId) {
              final match = characters.where((c) => c.id == characterId);
              if (match.isEmpty) return 'Unknown';
              return match.first.name;
            }

            // Build discipline options from the UNFILTERED list
            final List<String> disciplineOptions = allForDisciplineOptions
                .map((r) => r.discipline)
                .whereType<String>()
                .map((d) => d.trim())
                .where((d) => d.isNotEmpty)
                .toSet()
                .toList()
              ..sort();

            Widget labeledRow({
              required String label,
              required Widget field,
              Widget? trailing,
            }) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Text(label, style: Theme.of(ctx).textTheme.bodyMedium),
                  ),
                  Expanded(child: field),
                  if (trailing != null) ...[
                    const SizedBox(width: 10),
                    trailing,
                  ],
                ],
              );
            }

            final charField = DropdownButtonFormField<int?>(
              initialValue: characterFilterId,
              isExpanded: true,
              icon: const SizedBox.shrink(),
              decoration: const InputDecoration(
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('All'),
                ),
                for (final c in characters)
                  DropdownMenuItem<int?>(
                    value: c.id,
                    child: Text(c.name),
                  ),
              ],
              onChanged: (v) async {
                characterFilterId = v;
                await refresh();
              },
            );

            final charButtons = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    await _openManageCharactersDialog();

                    final updated = await _loadoutRepo.listCharacters();
                    characters = updated.toList();

                    setLocal(() {
                      characterFilterId = null;
                      disciplineFilter = null;
                      queryCtrl.text = '';
                    });

                    await refresh();
                  },
                  child: const Text('Manage Characters'),
                ),
              ],
            );

            final disciplineField = DropdownButtonFormField<String?>(
              initialValue: disciplineFilter,
              isExpanded: true,
              icon: const SizedBox.shrink(),
              decoration: const InputDecoration(
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All'),
                ),
                ...disciplineOptions.map(
                  (d) => DropdownMenuItem<String?>(
                    value: d,
                    child: Text(d),
                  ),
                ),
              ],
              onChanged: (v) async {
                disciplineFilter = v;
                await refresh();
              },
            );

            final searchField = TextField(
              controller: queryCtrl,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Loadout Name',
              ),
              onChanged: (_) => refresh(),
            );

            Future<void> clearFilters() async {
              setLocal(() {
                characterFilterId = null;
                disciplineFilter = null;
                queryCtrl.text = '';
              });
              await refresh();
            }

            return AlertDialog(
              title: const Text('Load Loadout'),
              content: Builder(
                builder: (innerCtx) {
                  final screen = MediaQuery.of(innerCtx).size;

                  final dialogW = (screen.width * 0.92).clamp(520.0, 760.0);
                  final dialogH = (screen.height * 0.80).clamp(420.0, 760.0);

                  // Header cap so the list always has room
                  final headerMaxH = (dialogH * 0.42).clamp(170.0, 260.0);

                  return SizedBox(
                    width: dialogW,
                    height: dialogH,
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [

                        Divider(color: Theme.of(innerCtx).dividerColor, height: 1),
                        const SizedBox(height: 10),

                        // ----- STICKY FILTER BAR -----
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: headerMaxH),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              labeledRow(label: 'Character', field: charField, trailing: charButtons),
                              const SizedBox(height: 10),
                              labeledRow(label: 'Discipline Filter', field: disciplineField),
                              const SizedBox(height: 10),
                              labeledRow(label: 'Search', field: searchField),
                              const SizedBox(height: 10),

                              // Clear Filters button under label column
                              Row(
                                children: [
                                  SizedBox(
                                    width: labelWidth,
                                    child: OutlinedButton(
                                      onPressed: clearFilters,
                                      child: const Text('Clear Filters'),
                                    ),
                                  ),
                                  const Expanded(child: SizedBox()),
                                ],
                              ),

                              const SizedBox(height: 10),
                              Divider(color: Theme.of(innerCtx).dividerColor, height: 1),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),

                        // ----- SCROLLING LIST -----
                        Expanded(
                          child: results.isEmpty
                              ? const Center(child: Text('No loadouts found.'))
                              : ListView.separated(
                                  itemCount: results.length,
                                  separatorBuilder: (_, _) => const Divider(height: 1),
                                  itemBuilder: (ctx2, i) {
                                      final r = results[i];
                                      return ListTile(
                                        isThreeLine: true,
                                        title: Text(
                                          '(${characterNameFor(r.characterId)}) ${r.name}',
                                          overflow: TextOverflow.ellipsis,
                                        ),

                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 2),

                                            // Line 1: class/spec (what you already had)
                                            Text(
                                              [
                                                if ((r.combatStyle ?? '').isNotEmpty) r.combatStyle!,
                                                if ((r.discipline ?? '').isNotEmpty) r.discipline!,
                                              ].join(' • '),
                                              overflow: TextOverflow.ellipsis,
                                            ),

                                            // Line 2: notes (only if present)
                                            if (((r.notes ?? '').trim()).isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                r.notes!.trim(),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(ctx).textTheme.bodySmall,
                                              ),
                                            ],
                                          ],
                                        ),

                                        // Text buttons instead of icons
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextButton(
                                              onPressed: () async {
                                                await _openEditLoadoutDialog(
                                                  ctx,
                                                  r,
                                                  onSaved: () async => refresh(),
                                                );
                                              },
                                              child: const Text('Edit'),
                                            ),
                                            const SizedBox(width: 4),
                                            TextButton(
                                              onPressed: () async {
                                                final newName = await _promptDuplicateName(ctx, r.name);
                                                if (newName == null) return;

                                                await _loadoutRepo.duplicateLoadout(r.id, newName: newName);
                                                await refresh();
                                              },
                                              child: const Text('Duplicate'),
                                            ),
                                            const SizedBox(width: 4),
                                            TextButton(
                                              onPressed: () async {
                                                try {
                                                  await _exportLoadoutFile(r);
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  showDialog<void>(
                                                    context: context,
                                                    builder: (ctx3) => AlertDialog(
                                                      title: const Text('Export failed'),
                                                      content: Text('$e'),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.of(ctx3).pop(),
                                                          child: const Text('OK'),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }
                                              },
                                              child: const Text('Export'),
                                            ),
                                            const SizedBox(width: 4),
                                            TextButton(
                                              onPressed: () async {
                                                final ok = await _confirmDeleteLoadout(ctx, r.name);
                                                if (!ok) return;

                                                await _loadoutRepo.deleteLoadout(r.id);
                                                await refresh();
                                              },
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),

                                        onTap: () async {
                                          final full = await _loadoutRepo.getLoadout(r.id);
                                          if (full == null) return;

                                          if (!mounted) return;
                                          _applyLoadout(full);

                                          if (!ctx.mounted) return;
                                          Navigator.of(ctx).pop();
                                        },
                                      );
                                  },
                              ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              actions: [
                OutlinedButton(
                  onPressed: () async {
                    await _importLoadoutFileAlwaysPromptCharacter();

                    final updated = await _loadoutRepo.listCharacters();
                    setLocal(() {
                      characters = updated.toList();
                    });

                    await refresh();
                  },
                  child: const Text('Import Loadout'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _promptDuplicateName(BuildContext ctx, String sourceName) async {
      final ctrl = TextEditingController(text: '$sourceName (Copy)');

      final res = await showDialog<String>(
        context: ctx,
        builder: (dctx) => AlertDialog(
          title: const Text('Duplicate Loadout'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'New loadout name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                Navigator.of(dctx).pop(name);
              },
              child: const Text('Create Copy'),
            ),
          ],
        ),
      );

      return res;
    }

  Future<bool> _confirmDeleteCharacter(BuildContext ctx, String characterName) async {
    final res = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Delete Character?'),
        content: Text(
          'Delete "$characterName" and ALL of its Loadouts?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<bool> _confirmDeleteLoadout(BuildContext ctx, String loadoutName) async {
    final res = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Delete loadout?'),
        content: Text('Delete "$loadoutName"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<String?> _promptRenameCharacter(BuildContext ctx, String currentName) async {
    final ctrl = TextEditingController(text: currentName);

    return showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Rename Character'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isEmpty) return;
              Navigator.of(dctx).pop(v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _openManageCharactersDialog() async {
    List<CharacterRow> chars = await _loadoutRepo.listCharacters();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> refresh() async {
              chars = await _loadoutRepo.listCharacters();
              if (!mounted) return;
              setLocal(() {});
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Expanded(child: Text('Manage Characters')),
                  TextButton(
                    onPressed: () async {
                      final id = await _createCharacterDialog();
                      if (id == null) return;
                      await refresh();
                    },
                    child: const Text('Create Character'),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: Column( 
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 8),

                    chars.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('No Characters Yet.'),
                        )
                      : SizedBox(
                          height: 360,
                          child: ListView.separated(
                            itemCount: chars.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (ctx2, i) {
                              final c = chars[i];

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Name
                                    Expanded(
                                      child: Text(
                                        c.name,
                                        style: Theme.of(ctx).textTheme.bodyLarge,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    const SizedBox(width: 12),

                                    // Actions (normal-sized TextButtons)
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: () async {
                                            final newName = await _promptRenameCharacter(ctx, c.name);
                                            if (newName == null) return;

                                            await _loadoutRepo.updateCharacter(
                                              id: c.id,
                                              name: newName,
                                            );
                                            await refresh();
                                          },
                                          child: const Text('Rename Character'),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            final ok = await _confirmDeleteCharacter(ctx, c.name);
                                            if (!ok) return;

                                            await _loadoutRepo.deleteCharacter(c.id);
                                            await refresh();
                                          },
                                          child: const Text('Delete Character'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportLoadoutFile(LoadoutSummary r) async {
    final transfer = LoadoutTransfer(_loadoutRepo);
    final jsonStr = await transfer.exportLoadoutToJson(r.id);

    final safeName = r.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final suggested = 'loadout_$safeName.json';

    final saveLocation = await getSaveLocation(
      suggestedName: suggested,
      acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'])],
    );
    if (saveLocation == null) return;

    final file = XFile.fromData(
      utf8.encode(jsonStr),
      mimeType: 'application/json',
      name: suggested,
    );

    await file.saveTo(saveLocation.path);

    if (!mounted) return;
    _showTotalsPaneSnackBar('Loadout exported.');
  }

  Future<void> _importLoadoutFileAlwaysPromptCharacter() async {
    final targetId = await _promptImportCharacterWithCreateButton();
    if (targetId == null) return;

    final xfile = await openFile(
      acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'])],
    );
    if (xfile == null) return;

    try {
      final jsonStr = utf8.decode(await xfile.readAsBytes());
      final transfer = LoadoutTransfer(_loadoutRepo);
      await transfer.importSingleLoadoutJson(jsonStr, targetCharacterId: targetId);

      if (!mounted) return;
      _showTotalsPaneSnackBar('Loadout imported successfully.');
    } on FormatException catch (e) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import failed'),
          content: Text(e.message),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import failed'),
          content: Text('Unexpected error: $e'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  Future<int?> _promptImportCharacterWithCreateButton() async {
  var chars = (await _loadoutRepo.listCharacters()).toList();
  if (!mounted) return null;

  // If no characters exist, let them create immediately (or cancel)
  if (chars.isEmpty) {
    final createdId = await _createCharacterDialog();
    return createdId; // may be null if cancelled
  }

  int selectedId = chars.first.id;

  final picked = await showDialog<int?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> refreshChars({int? selectId}) async {
          chars = (await _loadoutRepo.listCharacters()).toList();
          if (!ctx.mounted) return;

          if (chars.isEmpty) {
            // Shouldn't happen here, but be safe
            Navigator.of(ctx).pop(null);
            return;
          }

          setLocal(() {
            // keep selection if still valid, otherwise default to first
            final desired = selectId ?? selectedId;
            selectedId = chars.any((c) => c.id == desired) ? desired : chars.first.id;
          });
        }

        return AlertDialog(
          title: const Text('Import to Character'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selectedId,
                  isExpanded: true,
                  icon: const SizedBox.shrink(),
                  decoration: const InputDecoration(
                    labelText: 'Character',
                  ),
                  items: [
                    for (final c in chars)
                      DropdownMenuItem<int>(
                        value: c.id,
                        child: Text(c.name),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => selectedId = v);
                  },
                ),
                const SizedBox(height: 10),

                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () async {
                      final newId = await _createCharacterDialog();
                      if (newId == null) return;
                      await refreshChars(selectId: newId);
                    },
                    child: const Text('Create Character'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selectedId),
              child: const Text('Import'),
            ),
          ],
        );
      },
    ),
  );

  return picked;
  }

  Future<void> _openEditLoadoutDialog(
    BuildContext ctx,
    LoadoutSummary r, {
    required Future<void> Function() onSaved,
  }) async {
    // Characters list (growable)
    final characters = (await _loadoutRepo.listCharacters()).toList();
    if (!mounted) return;

    // Pull full loadout so we can edit notes
    final full = await _loadoutRepo.getLoadout(r.id);
    if (full == null) return;

    int selectedCharacterId = r.characterId;
    if (characters.isNotEmpty && !characters.any((c) => c.id == selectedCharacterId)) {
      selectedCharacterId = characters.first.id;
    }

    final nameCtrl = TextEditingController(text: r.name);
    final notesCtrl = TextEditingController(text: full.notes ?? '');

    await showDialog<void>(
      context: ctx,
      builder: (dctx) {
        return StatefulBuilder(
          builder: (dctx, setLocal) {
            return AlertDialog(
              title: const Text('Edit Loadout'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Loadout name'),
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<int>(
                      initialValue: selectedCharacterId,
                      isExpanded: true,
                      icon: const SizedBox.shrink(),
                      decoration: const InputDecoration(labelText: 'Character'),
                      items: [
                        for (final c in characters)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() => selectedCharacterId = v);
                      },
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        hintText: 'Optional Notes for this Loadout',
                      ),
                    ),

                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'This Renames/Reassigns the Loadout and edits Notes.\nClass/Spec and gear selections are unchanged.',
                        style: Theme.of(dctx).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final newName = nameCtrl.text.trim();
                    if (newName.isEmpty) return;

                    final newCharId = selectedCharacterId;
                    final newNotesTrim = notesCtrl.text.trim();
                    final notesValue = newNotesTrim.isEmpty ? null : newNotesTrim;

                    await _loadoutRepo.updateLoadoutMeta(
                      loadoutId: r.id,
                      name: newName,
                      characterId: newCharId,
                      notes: notesValue,
                      setNotes: true, // IMPORTANT: allows clearing notes to NULL
                    );

                    if (!dctx.mounted) return;
                    Navigator.of(dctx).pop();

                    await onSaved();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static const String _dismissedUpdateVersionKey = 'dismissed_update_version';
  static const String _lastKnownLatestVersionKey = 'last_known_latest_version';
  static const String _lastKnownInstallerUrlKey = 'last_known_installer_url';
  static const String _lastKnownNotesKey = 'last_known_notes';

  static bool _hasCheckedForUpdatesThisSession = false;

  Future<void> _checkForUpdates({bool manual = false}) async {
    final checker = UpdateChecker(
      Uri.parse('https://dantiko.github.io/dantiko-swtor-loadout-builder/update.json'),
    );

    try {
      final prefs = await SharedPreferences.getInstance();

      final shouldSkipNetworkCheck = !manual && _hasCheckedForUpdatesThisSession;

      UpdateInfo? info;

      if (shouldSkipNetworkCheck) {
        final package = await PackageInfo.fromPlatform();
        final cachedLatest = prefs.getString(_lastKnownLatestVersionKey);
        final cachedUrl = prefs.getString(_lastKnownInstallerUrlKey);
        final cachedNotes = prefs.getStringList(_lastKnownNotesKey) ?? const <String>[];

        if (cachedLatest != null && cachedUrl != null) {
          info = UpdateInfo(
            currentVersion: package.version,
            latestVersion: cachedLatest,
            installerUrl: cachedUrl,
            notes: cachedNotes,
          );
        }
      } else {
        info = await checker.check().timeout(const Duration(seconds: 5));

        _hasCheckedForUpdatesThisSession = true;

        if (info != null) {
          await prefs.setString(_lastKnownLatestVersionKey, info.latestVersion);
          await prefs.setString(_lastKnownInstallerUrlKey, info.installerUrl);
          await prefs.setStringList(_lastKnownNotesKey, info.notes);
        }
      }

      if (info == null) {
        if (manual && mounted) {
          _showTotalsPaneSnackBar('Unable to check for updates.');
        }
        return;
      }

      final updateInfo = info;

      if (!updateInfo.hasUpdate) {
        if (manual && mounted) {
          _showTotalsPaneSnackBar('You are running the latest version.');
        }
        return;
      }

      final dismissedVersion = prefs.getString(_dismissedUpdateVersionKey);

      if (!manual && dismissedVersion == updateInfo.latestVersion) {
        return;
      }

      if (!mounted) return;

      bool dontShowAgain = false;

      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              return AlertDialog(
                title: const Text('Update Available'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current version: ${updateInfo.currentVersion}'),
                    Text('Latest version: ${updateInfo.latestVersion}'),
                    const SizedBox(height: 12),
                    if (updateInfo.notes.isNotEmpty) ...[
                      const Text('What’s new:'),
                      const SizedBox(height: 6),
                      ...updateInfo.notes.map((n) => Text('• $n')),
                      const SizedBox(height: 12),
                    ],
                    CheckboxListTile(
                      value: dontShowAgain,
                      onChanged: (value) async {
                        final newValue = value ?? false;

                        if (!newValue) {
                          setLocal(() {
                            dontShowAgain = false;
                          });
                          return;
                        }

                        final confirm = await showDialog<bool>(
                          context: ctx,
                          builder: (confirmCtx) => AlertDialog(
                            title: const Text('Are you sure?'),
                            content: const Text(
                              'You will not be shown an update again until a new release is added.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(confirmCtx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(confirmCtx).pop(true),
                                child: const Text('Yes'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          setLocal(() {
                            dontShowAgain = true;
                          });
                        }
                      },
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text("Don't show again for this version"),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      if (dontShowAgain) {
                        await prefs.setString(
                          _dismissedUpdateVersionKey,
                          updateInfo.latestVersion,
                        );
                      }
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                    },
                    child: const Text('Close'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      await prefs.remove(_dismissedUpdateVersionKey);

                      final uri = Uri.parse(updateInfo.installerUrl);
                      await launchUrl(uri);

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                    },
                    child: const Text('Download'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e, st) {
      debugPrint('Update check failed: $e');
      debugPrint('$st');

      if (manual && mounted) {
        _showTotalsPaneSnackBar('Unable to check for updates: $e');
      }
    }
  }
}

/// ------------------------
/// Background frame
/// ------------------------

class _StatsBackgroundFrame extends StatelessWidget {
  final Widget child;
  const _StatsBackgroundFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/ui/stats_bg.png'),
          fit: BoxFit.cover, // stretch/crop as needed (you said that's fine)
        ),
      ),
      child: child,
    );
  }
}

class _BackgroundFrame extends StatelessWidget {
  final Widget child;
  const _BackgroundFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/ui/gear_bg.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: child,
    );
  }
}

/// ------------------------
/// Hitbox styling
/// ------------------------

class _SlotHitbox extends StatelessWidget {
  final VoidCallback onTap;
  final Color borderColor;
  final Color fillColor;
  final bool isSelected;

  const _SlotHitbox({
    super.key,
    required this.onTap,
    required this.borderColor,
    required this.fillColor,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: fillColor,
            border: Border.all(
              width: isSelected ? 2.5 : 1.3, // 👈 thinner when unselected
              color: borderColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// ------------------------
/// Slot ordering & anchors
/// ------------------------

const _weaponSlots = <GearSlot>[GearSlot.MAIN_HAND, GearSlot.OFF_HAND];

const _armorSlots = <GearSlot>[
  GearSlot.HEAD,
  GearSlot.CHEST,
  GearSlot.WRISTS,
  GearSlot.HANDS,
  GearSlot.WAIST,
  GearSlot.LEGS,
  GearSlot.FEET,
];

const _accessorySlots = <GearSlot>[
  GearSlot.EAR,
  GearSlot.IMPLANT_1,
  GearSlot.IMPLANT_2,
  GearSlot.RELIC_1,
  GearSlot.RELIC_2,
];

const _slotOrder = <GearSlot>[
  ..._weaponSlots,
  ..._armorSlots,
  ..._accessorySlots,
];

bool _slotUsesVariantToggle(GearSlot slot) => slot == GearSlot.WRISTS || slot == GearSlot.WAIST;

class _SlotAnchor {
  final double x, y, w, h;
  const _SlotAnchor(this.x, this.y, this.w, this.h);
}

/// Paste your tuned anchor values here (post-aspect-ratio-lock tuning).
const Map<GearSlot, _SlotAnchor> _slotAnchors = {
  // Weapons (top)
  GearSlot.MAIN_HAND: _SlotAnchor(0.3336, 0.1483, 0.1700, 0.0950),
  GearSlot.OFF_HAND:  _SlotAnchor(0.5289, 0.1483, 0.1700, 0.0950),

  // Armor (middle)
  GearSlot.HEAD:   _SlotAnchor(0.4310, 0.3515, 0.1700, 0.0950),
  GearSlot.CHEST:  _SlotAnchor(0.4310, 0.4585, 0.1700, 0.0950),
  GearSlot.WRISTS: _SlotAnchor(0.2284, 0.4585, 0.1700, 0.0950),
  GearSlot.HANDS:  _SlotAnchor(0.6310, 0.4585, 0.1700, 0.0950),
  GearSlot.WAIST:  _SlotAnchor(0.4310, 0.5655, 0.1700, 0.0950),
  GearSlot.LEGS:   _SlotAnchor(0.6310, 0.5625, 0.1700, 0.0950),
  GearSlot.FEET:   _SlotAnchor(0.2284, 0.5625, 0.1700, 0.0950),

  // Accessories (bottom)
  GearSlot.EAR:       _SlotAnchor(0.2284, 0.7697, 0.1700, 0.0950),
  GearSlot.IMPLANT_1: _SlotAnchor(0.4310, 0.7697, 0.1700, 0.0950),
  GearSlot.IMPLANT_2: _SlotAnchor(0.6310, 0.7697, 0.1700, 0.0950),
  GearSlot.RELIC_1:   _SlotAnchor(0.4310, 0.8757, 0.1700, 0.0950),
  GearSlot.RELIC_2:   _SlotAnchor(0.6310, 0.8757, 0.1700, 0.0950),
};

const _SlotAnchor _stimAnchor = _SlotAnchor(0.2284, 0.8757, 0.1700, 0.0950);

/// ------------------------
/// Slot state
/// ------------------------

class _SlotState {
  int? rating;
  StatFocus focus;
  String augmentKey;
  PreferredProfile preferredProfile;

  _SlotState({
    required this.rating,
    required this.focus,
    required this.augmentKey,
    required this.preferredProfile,
  });

  static _SlotState initialForSlot(GearSlot slot) => _SlotState(
    rating: null,
    focus: StatFocus.NONE,
    augmentKey: 'AUG_NONE',
    preferredProfile: _slotUsesVariantToggle(slot)
        ? PreferredProfile.DPS
        : PreferredProfile.AUTO, // won't matter for non-variant slots
  );

  void normalize(GearSlot slot) {
    if (rating == null) {
      focus = StatFocus.NONE;
      augmentKey = 'AUG_NONE';
      preferredProfile = _slotUsesVariantToggle(slot)
          ? PreferredProfile.DPS
          : PreferredProfile.AUTO;
      return;
    }

    final norm = SlotPolicy.normalizeSelection(slot: slot, rating: rating!, focus: focus);
    rating = norm.rating;
    focus = norm.focus;

    if (!_slotUsesVariantToggle(slot)) {
      preferredProfile = PreferredProfile.AUTO;
    }

    if (_slotUsesVariantToggle(slot) && preferredProfile == PreferredProfile.AUTO) {
      preferredProfile = PreferredProfile.DPS;
    }
  }
}

class SwtorPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double backgroundAlpha;
  final TextStyle? textStyle;
  final Widget? leading;
  final MainAxisAlignment alignment;

  const SwtorPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.backgroundAlpha = 0.45,
    this.textStyle,
    this.leading,
    this.alignment = MainAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    final style = textStyle ??
        const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        );

    return Material(
      color: Colors.black.withValues(alpha: enabled ? backgroundAlpha : 0.22),
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: alignment,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 6),
              ],
              Text(label, style: style),
            ],
          ),
        ),
      ),
    );
  }
}

class SwtorPillRow extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final WrapAlignment alignment;
  final WrapCrossAlignment crossAxisAlignment;

  const SwtorPillRow({
    super.key,
    required this.children,
    this.spacing = 10,
    this.runSpacing = 8,
    this.alignment = WrapAlignment.start,
    this.crossAxisAlignment = WrapCrossAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignment,
      crossAxisAlignment: crossAxisAlignment,
      spacing: spacing,
      runSpacing: runSpacing,
      children: children,
    );
  }
}

class SwtorPillBar extends StatelessWidget {
  final List<SwtorPillAction> actions;
  final double spacing;
  final double runSpacing;
  final WrapAlignment alignment;

  const SwtorPillBar({
    super.key,
    required this.actions,
    this.spacing = 10,
    this.runSpacing = 8,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return SwtorPillRow(
      spacing: spacing,
      runSpacing: runSpacing,
      alignment: alignment,
      children: [
        for (final a in actions)
          SwtorPillButton(
            label: a.label,
            onTap: a.onTap,
            leading: a.leading,
            padding: a.padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
      ],
    );
  }
}

class SwtorPillAction {
  final String label;
  final VoidCallback? onTap;
  final Widget? leading;
  final EdgeInsetsGeometry? padding;

  const SwtorPillAction({
    required this.label,
    required this.onTap,
    this.leading,
    this.padding,
  });
}

/// ------------------------
/// Dropdown widgets
/// ------------------------

class _AugmentCornerDot extends StatelessWidget {
  final Color color;
  const _AugmentCornerDot({required this.color});

  @override
  Widget build(BuildContext context) {
    if (color == Colors.transparent) return const SizedBox.shrink();

    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CornerIndicatorBox extends StatelessWidget {
  final Color color;
  final Alignment alignment;
  const _CornerIndicatorBox({
    required this.color,
    required this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    if (color == Colors.transparent) return const SizedBox.shrink();

    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  final String label;
  final T value;
  final Iterable<T> items;
  final ValueChanged<T> onChanged;
  final String Function(T) display;
  final bool enabled;

  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.display,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          icon: const SizedBox.shrink(),
          items: items
              .map((v) => DropdownMenuItem<T>(
                    value: v,
                    child: Text(display(v), overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
        ),
      ),
    );
  }
}

class _DropdownRowNullable<T> extends StatelessWidget {
  final String label;
  final T? value;
  final Iterable<T?> items;
  final ValueChanged<T?> onChanged;
  final String Function(T?) display;
  final bool enabled;

  const _DropdownRowNullable({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.display,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          isExpanded: true,
          value: value,
          icon: const SizedBox.shrink(),
          items: items
              .map((v) => DropdownMenuItem<T?>(
                    value: v,
                    child: Text(display(v), overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: enabled ? (v) => onChanged(v) : null,
        ),
      ),
    );
  }
}

Widget _ratingOverlayText({
  required int? gearRating,
  required int? augmentRating,
}) {
  // If no gear selected, show nothing at all
  if (gearRating == null) return const SizedBox.shrink();

  final gearText = gearRating.toString();
  final augText = (augmentRating != null) ? '(${augmentRating})' : '';

  return IgnorePointer(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          gearText,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.0,
            shadows: [
              Shadow(blurRadius: 2, offset: Offset(0, 1), color: Colors.black),
            ],
          ),
        ),

        // Only show augment rating if gear exists AND augment exists
        if (augText.isNotEmpty)
          Text(
            augText,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.0,
              shadows: [
                Shadow(blurRadius: 2, offset: Offset(0, 1), color: Colors.black),
              ],
            ),
          ),
      ],
    ),
  );
}



/// ------------------------
/// Helpers
/// ------------------------

Color _statLabelColor(String key) {
  switch (key.toLowerCase()) {
    case 'mastery':
      return const Color.fromARGB(255, 0, 120, 130); // dark cyan
    case 'endurance':
      return const Color.fromARGB(255, 0, 100, 40); // green
    case 'power':
      return const Color(0xFFFF9100); // orange

    case 'critical':
      return const Color.fromARGB(255, 255, 32, 32); // red
    case 'alacrity':
      return const Color.fromARGB(255, 0, 255, 0); // light green
    case 'accuracy':
      return const Color.fromARGB(255, 255, 255, 0); // gold

    case 'defense':
      return const Color.fromARGB(255, 255, 50, 255); // magenta
    case 'absorb':
      return const Color.fromARGB(255, 0, 110, 255); // dark blue
    case 'shield':
      return const Color.fromARGB(255, 0, 183, 255); // light blue

    default:
      return Colors.white70;
  }
}

Color _focusBorderColor(StatFocus focus) {
  switch (focus) {
    case StatFocus.CRITICAL:
      return const Color.fromARGB(255, 255, 32, 32); // red
    case StatFocus.ALACRITY:
      return const Color.fromARGB(255, 0, 255, 0); // light green
    case StatFocus.ACCURACY:
      return const Color.fromARGB(255, 255, 255, 0); // gold
    case StatFocus.SHIELD:
      return const Color.fromARGB(255, 0, 183, 255); // light blue
    case StatFocus.ABSORB:
      return const Color.fromARGB(255, 0, 110, 255); // dark blue
    case StatFocus.NONE:
      return Colors.transparent;
  }
}

Color _secondaryFillColorFromStats(StatBundle b) {
  // If the item has any tank-flavored stats, show tank (grey) inlay.
  // This covers shield/absorb variants even if defense happens to be 0.
  final hasDefensiveStats = (b.defense > 0) || (b.shield > 0) || (b.absorb > 0);
  if (hasDefensiveStats) {
    return const Color.fromARGB(255, 255, 50, 255); // magenta
  }

  // Otherwise, if it has power, show DPS (orange) inlay.
  if (b.power > 0) {
    return const Color(0xFFFF9100); // orange
  }

  return Colors.transparent;
}

Color _primaryStatColorFromStim(StatBundle b) {
  // Primary stats (choose the first non-zero, in typical “stim primary” priority)
  if (b.accuracy > 0) return const Color.fromARGB(255, 255, 255, 0); // accuracy
  if (b.mastery > 0) return const Color.fromARGB(255, 0, 120, 130); // mastery
  if (b.endurance > 0) return const Color.fromARGB(255, 0, 100, 40); // endurance

  return Colors.transparent;
}

Color _secondaryStatColorFromStim(StatBundle b) {
  // Secondary stats (focus-like)
  if (b.critical > 0) return const Color.fromARGB(255, 255, 32, 32); // critical
  if (b.power > 0) return const Color(0xFFFF9100); // power
  if (b.defense > 0) return const Color.fromARGB(255, 255, 50, 255); // defense

  return Colors.transparent;
}

Color _augmentIndicatorColor(StatBundle b) {
  if (b.critical > 0) return const Color.fromARGB(255, 255, 0, 0); // critical red
  if (b.alacrity > 0) return const Color.fromARGB(255, 0, 255, 0); // alacrity green
  if (b.accuracy > 0) return const Color.fromARGB(255, 255, 255, 0); // accuracy gold
  if (b.shield > 0) return const Color.fromARGB(255, 0, 183, 255); // shield light blue
  if (b.absorb > 0) return const Color.fromARGB(255, 0, 110, 255); // absorb dark blue
  if (b.mastery > 0) return const Color.fromARGB(255, 0, 120, 130); // mastery dark cyan
  if (b.defense > 0) return const Color.fromARGB(255, 255, 50, 255); // defense magenta
  return Colors.transparent;
}

Color _crystalIndicatorColor(StatBundle b) {
  if (b.critical > 0) return const Color.fromARGB(255, 255, 0, 0); // critical
  if (b.mastery > 0) return const Color.fromARGB(255, 0, 120, 130); // mastery
  if (b.power > 0) return const Color(0xFFFF9100); // power
  if (b.endurance > 0) return const Color.fromARGB(255, 0, 100, 40); // endurance
  return Colors.transparent;
}

int _getStatValue(StatBundle b, String key) {
  switch (key.toLowerCase()) {
    case 'mastery':
      return b.mastery;
    case 'endurance':
      return b.endurance;
    case 'power':
      return b.power;
    case 'critical':
      return b.critical;
    case 'alacrity':
      return b.alacrity;
    case 'accuracy':
      return b.accuracy;
    case 'defense':
      return b.defense;
    case 'absorb':
      return b.absorb;
    case 'shield':
      return b.shield;
    default:
      // If you later add more stats, decide how you store them.
      // For now, unknown stats show 0.
      return 0;
  }
}

int? _augmentRatingFromKey(String augmentKey) {
  // Expected patterns like: "AUG_344_CRITICAL" or "AUG_340_ALACRITY" etc.
  // Returns null for AUG_NONE or unexpected formats.
  if (augmentKey == 'AUG_NONE') return null;

  final parts = augmentKey.split('_');
  if (parts.length < 2) return null;

  return int.tryParse(parts[1]);
}

List<int> _ratingOptionsForSlot(GearSlot slot) {
  const all = <int>[324, 326, 328, 330, 332, 334, 336, 338, 340, 342, 344];
  if (slot == GearSlot.IMPLANT_1 || slot == GearSlot.IMPLANT_2) {
    return const <int>[326, 328, 330, 332, 334, 336, 338, 340];
  }
  return all;
}

List<T> _sortedKeys<T extends String>(Iterable<T> keys) {
  final list = keys.toList();
  list.sort();
  return list;
}

String _friendlyKeyLabel(String key) {
  if (key == 'AUG_NONE' || key == 'STIM_NONE' || key == 'CRYSTAL_NONE') return 'None';
  final parts = key.split('_');
  if (parts.isEmpty) return key;

  if (parts.first == 'AUG' && parts.length >= 3) {
    return '${parts[1]} ${_title(parts.sublist(2).join(" "))} Augment';
  }
  if (parts.first == 'STIM' && parts.length >= 2) {
    return '${_title(parts.sublist(1).join(" "))} Stim';
  }
  if (parts.first == 'CRYSTAL' && parts.length >= 2) {
    return '${_title(parts.sublist(1).join(" "))} Crystal';
  }
  return _title(parts.join(' '));
}

String _title(String s) {
  return s
      .toLowerCase()
      .split(RegExp(r'\s+|_+'))
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1))
      .join(' ');
}

String _focusLabel(StatFocus f) {
  switch (f) {
    case StatFocus.CRITICAL:
      return 'Critical';
    case StatFocus.ALACRITY:
      return 'Alacrity';
    case StatFocus.ACCURACY:
      return 'Accuracy';
    case StatFocus.SHIELD:
      return 'Shield';
    case StatFocus.ABSORB:
      return 'Absorb';
    case StatFocus.NONE:
      return 'None';
  }
}

String _preferredProfileLabel(PreferredProfile p) {
  switch (p) {
    case PreferredProfile.AUTO:
      return 'Auto';
    case PreferredProfile.DPS:
      return 'DPS';
    case PreferredProfile.TANK:
      return 'Tank';
  }
}

String _gearSlotLabel(GearSlot s) {
  switch (s) {
    case GearSlot.HEAD:
      return 'Head';
    case GearSlot.CHEST:
      return 'Chest';
    case GearSlot.WRISTS:
      return 'Wrists';
    case GearSlot.HANDS:
      return 'Hands';
    case GearSlot.WAIST:
      return 'Waist';
    case GearSlot.LEGS:
      return 'Legs';
    case GearSlot.FEET:
      return 'Feet';
    case GearSlot.MAIN_HAND:
      return 'Main Hand';
    case GearSlot.OFF_HAND:
      return 'Off Hand';
    case GearSlot.EAR:
      return 'Ear';
    case GearSlot.IMPLANT_1:
      return 'Implant 1';
    case GearSlot.IMPLANT_2:
      return 'Implant 2';
    case GearSlot.RELIC_1:
      return 'Relic 1';
    case GearSlot.RELIC_2:
      return 'Relic 2';
  }
}

String _prettyStatName(String raw) {
  final key = raw.toLowerCase();

  // Custom display overrides
  switch (key) {
    case 'critical':
      return 'Critical';
    case 'alacrity':
      return 'Alacrity';
    case 'accuracy':
      return 'Accuracy';
    case 'defense':
      return 'Defense';
    case 'absorb':
      return 'Absorb';
    case 'shield':
      return 'Shield';
    case 'mastery':
      return 'Mastery';
    case 'endurance':
      return 'Endurance';
    case 'power':
      return 'Power';
  }

  // Fallback: auto title-case
  final s = raw.replaceAll('_', ' ').trim();
  if (s.isEmpty) return raw;

  final words = s.split(RegExp(r'\s+'));
  return words
      .map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1).toLowerCase()))
      .join(' ');
}

String _fmtPct(double? v, {int decimals = 2}) {
  // Treat v as "percentage points" (e.g., 12.34 means 12.34%)
  if (v == null) return '0.00%';
  return '${v.toStringAsFixed(decimals)}%';
}

/// ------------------------
/// Debug overlay (optional)
/// ------------------------
/// If you still have your existing anchor debug overlay widget in your project,
/// keep it. This placeholder prevents compile errors if you left kAnchorDebug=false.
class _AnchorDebugOverlay extends StatelessWidget {
  const _AnchorDebugOverlay();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}