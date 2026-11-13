import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/puzzle.dart';

List<Puzzle> _parsePuzzlesJson(String jsonString) {
  final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
  return jsonList.map((e) => Puzzle.fromJson(e as Map<String, dynamic>)).toList();
}

class PuzzleService {
  static final PuzzleService _instance = PuzzleService._internal();
  factory PuzzleService() => _instance;
  PuzzleService._internal();

  static const String _keyStepbackHistory = 'puzzle_history_stepback_v1';
  static const String _keyWoodpeckerHistory = 'puzzle_history_woodpecker_v1';

  final Random _random = Random();
  List<Puzzle> _allPuzzles = [];
  final Map<String, Puzzle> _puzzleById = {};
  final List<String> _stepbackHistory = []; // Oldest first, newest last
  final List<String> _woodpeckerHistory = []; // Oldest first, newest last
  bool _isLoaded = false;

  Future<void> loadPuzzles() async {
    if (_isLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStepback = prefs.getStringList(_keyStepbackHistory) ?? [];
      final savedWoodpecker = prefs.getStringList(_keyWoodpeckerHistory) ?? [];
      _stepbackHistory
        ..clear()
        ..addAll(savedStepback);
      _woodpeckerHistory
        ..clear()
        ..addAll(savedWoodpecker);

      final jsonString = await rootBundle.loadString('assets/data/puzzles.json');
      _allPuzzles = await compute(_parsePuzzlesJson, jsonString);
      _puzzleById.clear();
      for (final p in _allPuzzles) {
        _puzzleById[p.id] = p;
      }
      _isLoaded = true;
    } catch (e) {
      _allPuzzles = [];
    }
  }

  void _recordUsedPuzzles(List<String> historyList, String prefsKey, Iterable<String> ids) {
    for (final id in ids) {
      historyList.remove(id);
      historyList.add(id);
    }
    if (historyList.length > 4000) {
      historyList.removeRange(0, historyList.length - 4000);
    }
    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList(prefsKey, List<String>.from(historyList));
    });
  }

  Puzzle? getPuzzleById(String id) => _puzzleById[id];

  /// Returns recommended difficulty tier id ('easy', 'medium', 'hard', 'master')
  /// based on the player's current app ELO rating.
  static String getRecommendedTierForElo(int elo) {
    if (elo < 1320) return 'easy';
    if (elo < 1550) return 'medium';
    if (elo < 1750) return 'hard';
    return 'master';
  }

  static int getTierRank(String tierId) {
    switch (tierId) {
      case 'easy':
        return 1;
      case 'medium':
        return 2;
      case 'hard':
        return 3;
      case 'master':
        return 4;
      default:
        return 0;
    }
  }

  static String getTierDisplayName(String tierId) {
    switch (tierId) {
      case 'easy':
        return 'Easy (<1350)';
      case 'medium':
        return 'Medium (1350-1550)';
      case 'hard':
        return 'Hard (1550-1750)';
      case 'master':
        return 'Master (1750+)';
      case 'auto':
      default:
        return 'Auto (Recommended)';
    }
  }

  /// Checks whether the selected difficulty tier is lower than recommended for the user's ELO.
  /// If true, the puzzle should be played Unrated.
  static bool isTierBelowRecommended(String selectedTier, int userElo) {
    if (selectedTier == 'auto') return false;
    final rec = getRecommendedTierForElo(userElo);
    return getTierRank(selectedTier) < getTierRank(rec);
  }

  /// Resolves rating bounds and forcing filter for a given tier or 'auto'.
  static ({int minRating, int maxRating, bool forcingOnly}) getFilterForTier(
    String tierId,
    int userElo,
  ) {
    final effectiveTier = tierId == 'auto' ? getRecommendedTierForElo(userElo) : tierId;
    switch (effectiveTier) {
      case 'easy':
        return (minRating: 800, maxRating: 1360, forcingOnly: true);
      case 'medium':
        return (minRating: 1350, maxRating: 1560, forcingOnly: true);
      case 'hard':
        return (minRating: 1550, maxRating: 1750, forcingOnly: false);
      case 'master':
        return (minRating: 1720, maxRating: 2800, forcingOnly: false);
      default:
        return (minRating: 1350, maxRating: 1560, forcingOnly: true);
    }
  }

  List<Puzzle> getFilteredPuzzles({
    int minRating = 800,
    int maxRating = 2800,
    bool forcingOnly = true,
    int minPreMoves = 0,
    int? maxPly,
  }) {
    if (_allPuzzles.isEmpty) return [];

    return _allPuzzles.where((p) {
      if (p.rating < minRating || p.rating > maxRating) return false;
      if (forcingOnly && p.forcingScore < 2) return false;
      if (minPreMoves > 0) {
        final available = p.gameMoves.isNotEmpty ? (p.ply - 1) : p.preMoves.length;
        if (available < minPreMoves) return false;
      }
      if (maxPly != null && p.ply > maxPly) return false;
      return true;
    }).toList();
  }

  Puzzle? getRandomPuzzle({
    int minRating = 800,
    int maxRating = 2800,
    bool forcingOnly = true,
    int minPreMoves = 0,
    int? maxPly,
  }) {
    // 1. Exact filter
    var list = getFilteredPuzzles(
      minRating: minRating,
      maxRating: maxRating,
      forcingOnly: forcingOnly,
      minPreMoves: minPreMoves,
      maxPly: maxPly,
    );

    // 2. Keep rating tier & maxPly, relax forcingOnly
    if (list.isEmpty && forcingOnly) {
      list = getFilteredPuzzles(
        minRating: minRating,
        maxRating: maxRating,
        forcingOnly: false,
        minPreMoves: minPreMoves,
        maxPly: maxPly,
      );
    }

    // 3. Relax maxPly slightly if Full Game mode had too narrow rating+ply intersection
    if (list.isEmpty && maxPly != null) {
      list = getFilteredPuzzles(
        minRating: minRating,
        maxRating: maxRating,
        forcingOnly: false,
        minPreMoves: minPreMoves,
        maxPly: maxPly + 16,
      );
    }

    // 4. Widen rating window slightly by 180 points without resetting to 800..2800
    if (list.isEmpty) {
      list = getFilteredPuzzles(
        minRating: max(800, minRating - 180),
        maxRating: min(2800, maxRating + 180),
        forcingOnly: false,
        minPreMoves: minPreMoves,
      );
    }

    // 5. Ultimate fallback
    if (list.isEmpty) {
      list = getFilteredPuzzles(
        minRating: 800,
        maxRating: 2800,
        forcingOnly: false,
        minPreMoves: minPreMoves,
      );
    }

    if (list.isEmpty) {
      return _allPuzzles.isNotEmpty
          ? _allPuzzles[_random.nextInt(_allPuzzles.length)]
          : null;
    }

    final usedSet = _stepbackHistory.toSet();
    final unseen = list.where((p) => !usedSet.contains(p.id)).toList();

    Puzzle chosen;
    if (unseen.isNotEmpty) {
      chosen = unseen[_random.nextInt(unseen.length)];
    } else {
      // All puzzles in this filter have been seen: pick from the OLDEST seen puzzles (never the most recent!)
      final indexMap = <String, int>{};
      for (int i = 0; i < _stepbackHistory.length; i++) {
        indexMap[_stepbackHistory[i]] = i;
      }
      final sortedByOldest = List<Puzzle>.from(list)
        ..sort((a, b) => (indexMap[a.id] ?? 0).compareTo(indexMap[b.id] ?? 0));
      final oldestWindow = max(1, (sortedByOldest.length * 0.25).round());
      chosen = sortedByOldest[_random.nextInt(oldestWindow)];
    }

    _recordUsedPuzzles(_stepbackHistory, _keyStepbackHistory, [chosen.id]);
    return chosen;
  }

  /// Generates a fixed set of `count` puzzles for Woodpecker Rush.
  /// Prioritizes completely unseen puzzles in the chosen tier; if the tier runs out,
  /// falls back to the OLDEST previously used puzzles (never the most recent sets!).
  List<Puzzle> generateWoodpeckerSet({
    required int count,
    required String difficultyTier,
    required int userElo,
  }) {
    final filter = getFilterForTier(difficultyTier, userElo);
    var pool = getFilteredPuzzles(
      minRating: filter.minRating,
      maxRating: filter.maxRating,
      forcingOnly: false,
    );
    if (pool.length < count) {
      pool = getFilteredPuzzles(
        minRating: max(800, filter.minRating - 200),
        maxRating: min(2800, filter.maxRating + 200),
        forcingOnly: false,
      );
    }
    if (pool.length < count) {
      pool = List<Puzzle>.from(_allPuzzles);
    } else {
      pool = List<Puzzle>.from(pool);
    }

    final usedSet = _woodpeckerHistory.toSet();
    final unseen = pool.where((p) => !usedSet.contains(p.id)).toList()..shuffle(_random);

    final selected = <Puzzle>[];
    if (unseen.length >= count) {
      selected.addAll(unseen.take(count));
    } else {
      // Take all remaining unseen puzzles first
      selected.addAll(unseen);
      final needed = count - selected.length;

      // Fill the rest with the OLDEST used puzzles in this tier (so recent sets are never repeated)
      final indexMap = <String, int>{};
      for (int i = 0; i < _woodpeckerHistory.length; i++) {
        indexMap[_woodpeckerHistory[i]] = i;
      }
      final seenInPool = pool.where((p) => usedSet.contains(p.id)).toList()
        ..sort((a, b) => (indexMap[a.id] ?? 0).compareTo(indexMap[b.id] ?? 0));

      selected.addAll(seenInPool.take(needed));
      selected.shuffle(_random);
    }

    _recordUsedPuzzles(
      _woodpeckerHistory,
      _keyWoodpeckerHistory,
      selected.map((p) => p.id),
    );
    return selected;
  }
}
