import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_stats.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static const String _keyStreak = 'streak_days';
  static const String _keyLastDate = 'last_trained_date';
  static const String _keyPathfinderLevel = 'pathfinder_level';
  static const String _keyCoordsHighScore = 'coords_highscore';
  static const String _keyPuzzlesSolved = 'total_puzzles_solved';
  static const String _keyTotalAttempts = 'total_attempts';
  static const String _keyElo = 'user_elo';
  static const String _keyEnergyCount = 'energy_count';
  static const String _keyLastEnergyReset = 'last_energy_reset';
  static const String _keyBoardTheme = 'board_theme';
  static const String _keyPreviousStreak = 'previous_streak';

  // Monthly XP & Woodpecker keys
  static const String _keyMonthlyXp = 'monthly_xp';
  static const String _keyMonthlyXpMonth = 'monthly_xp_month';
  static const String _keyWoodpeckerSetsCompleted = 'woodpecker_sets_completed';
  static const String _keyWoodpeckerState = 'woodpecker_active_state_v1';
  static const String _keyEloResetV2Done = 'elo_reset_v2_done';

  static const int maxEnergy = 10;

  final ValueNotifier<String> boardThemeNotifier = ValueNotifier<String>('slate');

  // Optional callback so LeaderboardService can auto-sync when stats change
  VoidCallback? onStatsUpdated;

  Future<int> getRemainingEnergy() async {
    final prefs = await SharedPreferences.getInstance();
    final lastReset = prefs.getInt(_keyLastEnergyReset) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (lastReset == 0 || (now - lastReset) >= 3600000) {
      await prefs.setInt(_keyEnergyCount, maxEnergy);
      await prefs.setInt(_keyLastEnergyReset, now);
      return maxEnergy;
    }

    return prefs.getInt(_keyEnergyCount) ?? maxEnergy;
  }

  Future<bool> consumeEnergy() async {
    final energy = await getRemainingEnergy();
    if (energy <= 0) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyEnergyCount, energy - 1);
    return true;
  }

  Future<void> refillEnergy() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_keyEnergyCount, maxEnergy);
    await prefs.setInt(_keyLastEnergyReset, now);
  }

  Future<int> getSecondsUntilEnergyReset() async {
    final prefs = await SharedPreferences.getInstance();
    final lastReset = prefs.getInt(_keyLastEnergyReset) ?? 0;
    if (lastReset == 0) return 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedSec = (now - lastReset) ~/ 1000;
    final remainingSec = 3600 - elapsedSec;
    return remainingSec > 0 ? remainingSec : 0;
  }

  Future<int> _getAndNormalizeMonthlyXp(SharedPreferences prefs) async {
    final currentMonth = _getCurrentMonthKey();
    final savedMonth = prefs.getString(_keyMonthlyXpMonth) ?? '';
    if (savedMonth != currentMonth) {
      await prefs.setString(_keyMonthlyXpMonth, currentMonth);
      await prefs.setInt(_keyMonthlyXp, 0);
      return 0;
    }
    return prefs.getInt(_keyMonthlyXp) ?? 0;
  }

  Future<int> addMonthlyXp(int xpDelta) async {
    if (xpDelta <= 0) return 0;
    final prefs = await SharedPreferences.getInstance();
    final currentXp = await _getAndNormalizeMonthlyXp(prefs);
    final updated = currentXp + xpDelta;
    await prefs.setInt(_keyMonthlyXp, updated);
    return updated;
  }

  Future<void> _ensureEloResetV2(SharedPreferences prefs) async {
    final hasResetEloV2 = prefs.getBool(_keyEloResetV2Done) ?? false;
    if (!hasResetEloV2) {
      if (prefs.containsKey(_keyElo)) {
        await prefs.setInt(_keyElo, 1200);
      }
      await prefs.setBool(_keyEloResetV2Done, true);
    }
  }

  Future<UserStats> loadUserStats() async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureEloResetV2(prefs);

    int streak = prefs.getInt(_keyStreak) ?? 0;
    String lastDate = prefs.getString(_keyLastDate) ?? '';

    // Check if streak is broken (more than 1 day missed)
    final today = _getTodayString();
    if (lastDate.isNotEmpty && lastDate != today) {
      final lastDateTime = DateTime.tryParse(lastDate);
      if (lastDateTime != null) {
        final diff = _daysBetween(lastDateTime, DateTime.now());
        if (diff > 1) {
          if (streak > 0) {
            await prefs.setInt(_keyPreviousStreak, streak);
          }
          streak = 0;
          await prefs.setInt(_keyStreak, 0);
        }
      }
    }

    final previousStreak = prefs.getInt(_keyPreviousStreak) ?? 0;
    final monthlyXp = await _getAndNormalizeMonthlyXp(prefs);

    return UserStats(
      streakDays: streak,
      lastTrainedDate: lastDate,
      pathfinderLevel: prefs.getInt(_keyPathfinderLevel) ?? 1,
      coordinatesHighScore: prefs.getInt(_keyCoordsHighScore) ?? 0,
      totalPuzzlesSolved: prefs.getInt(_keyPuzzlesSolved) ?? 0,
      totalAttempts: prefs.getInt(_keyTotalAttempts) ?? 0,
      eloRating: prefs.getInt(_keyElo) ?? 1200,
      monthlyXp: monthlyXp,
      woodpeckerSetsCompleted: prefs.getInt(_keyWoodpeckerSetsCompleted) ?? 0,
      canRestoreStreak: streak == 0 && previousStreak > 0,
    );
  }

  /// Calculates realistic Elo rating delta using standard Elo expected score
  /// adjusted for puzzle rating and mental visualization depth.
  int calculateEloDelta({
    required int currentElo,
    required int puzzleRating,
    required int visualizationDepth,
    required bool success,
  }) {
    final int depthBonus = visualizationDepth >= 100
        ? 240
        : ((visualizationDepth - 1) * 35).clamp(0, 220);
    final int effectivePuzzleRating = (puzzleRating + depthBonus).clamp(800, 2600);

    final double expected =
        1.0 / (1.0 + pow(10.0, (effectivePuzzleRating - currentElo) / 400.0));
    const double kFactor = 28.0;

    if (success) {
      return (kFactor * (1.0 - expected)).round().clamp(2, 26);
    } else {
      return -(kFactor * expected).round().clamp(3, 26);
    }
  }

  /// Records a flawless rated Stepback puzzle solve.
  /// Returns the ELO delta gained.
  Future<int> recordRatedPuzzleSuccess({
    required int puzzleRating,
    required int visualizationDepth,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureEloResetV2(prefs);
    int solved = prefs.getInt(_keyPuzzlesSolved) ?? 0;
    int attempts = prefs.getInt(_keyTotalAttempts) ?? 0;
    int elo = prefs.getInt(_keyElo) ?? 1200;

    final int delta = calculateEloDelta(
      currentElo: elo,
      puzzleRating: puzzleRating,
      visualizationDepth: visualizationDepth,
      success: true,
    );

    solved++;
    attempts++;
    elo = (elo + delta).clamp(800, 3000);

    await prefs.setInt(_keyTotalAttempts, attempts);
    await prefs.setInt(_keyPuzzlesSolved, solved);
    await prefs.setInt(_keyElo, elo);

    final int depthXp = visualizationDepth >= 100 ? 15 : (visualizationDepth * 2);
    await addMonthlyXp(12 + depthXp);
    await updateStreak();
    onStatsUpdated?.call();
    return delta;
  }

  /// Records the first mistake on a rated Stepback puzzle.
  /// Deducts ELO immediately and returns the negative ELO delta.
  Future<int> recordRatedPuzzleMistake({
    required int puzzleRating,
    required int visualizationDepth,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureEloResetV2(prefs);
    int attempts = prefs.getInt(_keyTotalAttempts) ?? 0;
    int elo = prefs.getInt(_keyElo) ?? 1200;

    final int delta = calculateEloDelta(
      currentElo: elo,
      puzzleRating: puzzleRating,
      visualizationDepth: visualizationDepth,
      success: false,
    );

    attempts++;
    elo = (elo + delta).clamp(800, 3000);

    await prefs.setInt(_keyTotalAttempts, attempts);
    await prefs.setInt(_keyElo, elo);
    onStatsUpdated?.call();
    return delta;
  }

  /// Records puzzle completion when the puzzle was either Unrated
  /// OR already had a mistake recorded (so ELO is not added back!).
  Future<void> recordPuzzleCompletionWithoutElo({
    required int xpEarned,
    bool countAttempt = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    int solved = prefs.getInt(_keyPuzzlesSolved) ?? 0;
    int attempts = prefs.getInt(_keyTotalAttempts) ?? 0;

    solved++;
    if (countAttempt) {
      attempts++;
      await prefs.setInt(_keyTotalAttempts, attempts);
    }
    await prefs.setInt(_keyPuzzlesSolved, solved);

    await addMonthlyXp(xpEarned);
    await updateStreak();
    onStatsUpdated?.call();
  }

  /// Records training activity for non-ELO modes (Coordinates, Pathfinder, Woodpecker).
  /// Does NOT modify ELO rating; updates Daily Streak and Monthly XP!
  Future<void> recordModeTraining({
    required int xpEarned,
    int puzzlesSolvedDelta = 0,
    bool updateDailyStreak = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (puzzlesSolvedDelta > 0) {
      final int solved = prefs.getInt(_keyPuzzlesSolved) ?? 0;
      final int attempts = prefs.getInt(_keyTotalAttempts) ?? 0;
      await prefs.setInt(_keyPuzzlesSolved, solved + puzzlesSolvedDelta);
      await prefs.setInt(_keyTotalAttempts, attempts + puzzlesSolvedDelta);
    }
    if (xpEarned > 0) {
      await addMonthlyXp(xpEarned);
    }
    if (updateDailyStreak) {
      await updateStreak();
    }
    onStatsUpdated?.call();
  }

  Future<void> incrementWoodpeckerSetsCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_keyWoodpeckerSetsCompleted) ?? 0;
    await prefs.setInt(_keyWoodpeckerSetsCompleted, current + 1);
    onStatsUpdated?.call();
  }

  Future<Map<String, dynamic>?> loadWoodpeckerState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyWoodpeckerState);
    if (raw == null || raw.isEmpty) return null;
    try {
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveWoodpeckerState(Map<String, dynamic> state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWoodpeckerState, json.encode(state));
  }

  Future<void> updateStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _getTodayString();
    String lastDate = prefs.getString(_keyLastDate) ?? '';
    int streak = prefs.getInt(_keyStreak) ?? 0;

    if (lastDate != today) {
      if (lastDate.isEmpty) {
        streak = 1;
      } else {
        final lastDateTime = DateTime.tryParse(lastDate);
        if (lastDateTime != null) {
          final diff = _daysBetween(lastDateTime, DateTime.now());
          if (diff == 1) {
            streak++;
          } else if (diff > 1) {
            if (streak > 0) {
              await prefs.setInt(_keyPreviousStreak, streak);
            }
            streak = 1;
          }
        }
      }
      await prefs.setString(_keyLastDate, today);
      await prefs.setInt(_keyStreak, streak);
    } else if (streak == 0) {
      streak = 1;
      await prefs.setInt(_keyStreak, streak);
    }
  }

  int _daysBetween(DateTime from, DateTime to) {
    final fromDate = DateTime(from.year, from.month, from.day);
    final toDate = DateTime(to.year, to.month, to.day);
    return toDate.difference(fromDate).inDays;
  }

  Future<void> savePathfinderLevel(int level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPathfinderLevel, level);
  }

  Future<void> saveCoordsHighScore(int score) async {
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt(_keyCoordsHighScore) ?? 0;
    if (score > current) {
      await prefs.setInt(_keyCoordsHighScore, score);
    }
  }

  Future<int> restoreStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _getTodayString();
    final current = prefs.getInt(_keyStreak) ?? 0;
    final prev = prefs.getInt(_keyPreviousStreak) ?? 1;
    final restored = current > prev ? current : (prev > 0 ? prev : 1);
    await prefs.setInt(_keyStreak, restored);
    await prefs.setInt(_keyPreviousStreak, 0);
    await prefs.setString(_keyLastDate, today);
    return restored;
  }

  String _getTodayString() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  String _getCurrentMonthKey() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}";
  }

  String get currentMonthKey => _getCurrentMonthKey();

  Future<bool> hasSeenModeInfo(String modeKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('seen_info_$modeKey') ?? false;
  }

  Future<void> setSeenModeInfo(String modeKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_info_$modeKey', true);
  }

  Future<String> loadBoardTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString(_keyBoardTheme) ?? 'slate';
    boardThemeNotifier.value = theme;
    return theme;
  }

  Future<void> saveBoardTheme(String themeId) async {
    boardThemeNotifier.value = themeId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_theme_picker', true);
    await prefs.setString(_keyBoardTheme, themeId);
  }
}
