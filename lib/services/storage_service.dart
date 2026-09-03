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
  static const int maxEnergy = 10;

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


  static const String _keyPreviousStreak = 'previous_streak';

  Future<UserStats> loadUserStats() async {
    final prefs = await SharedPreferences.getInstance();
    
    int streak = prefs.getInt(_keyStreak) ?? 0;
    String lastDate = prefs.getString(_keyLastDate) ?? '';
    
    // Check if streak is broken (more than 1 day missed)
    final today = _getTodayString();
    if (lastDate.isNotEmpty && lastDate != today) {
      final lastDateTime = DateTime.tryParse(lastDate);
      if (lastDateTime != null) {
        final diff = _daysBetween(lastDateTime, DateTime.now());
        if (diff > 1) {
          // Save broken streak so it can be restored
          if (streak > 0) {
            await prefs.setInt(_keyPreviousStreak, streak);
          }
          streak = 0;
        }
      }
    }

    return UserStats(
      streakDays: streak,
      lastTrainedDate: lastDate,
      pathfinderLevel: prefs.getInt(_keyPathfinderLevel) ?? 1,
      coordinatesHighScore: prefs.getInt(_keyCoordsHighScore) ?? 0,
      totalPuzzlesSolved: prefs.getInt(_keyPuzzlesSolved) ?? 0,
      totalAttempts: prefs.getInt(_keyTotalAttempts) ?? 0,
      eloRating: prefs.getInt(_keyElo) ?? 1200,
    );
  }

  Future<void> recordActivity(bool success) async {
    final prefs = await SharedPreferences.getInstance();
    int solved = prefs.getInt(_keyPuzzlesSolved) ?? 0;
    int attempts = prefs.getInt(_keyTotalAttempts) ?? 0;
    int elo = prefs.getInt(_keyElo) ?? 1200;

    attempts++;
    if (success) {
      solved++;
      elo += 12;
    } else {
      elo = (elo - 8).clamp(800, 3000);
    }

    await prefs.setInt(_keyTotalAttempts, attempts);
    await prefs.setInt(_keyPuzzlesSolved, solved);
    await prefs.setInt(_keyElo, elo);

    await updateStreak();
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
    int prev = prefs.getInt(_keyPreviousStreak) ?? 1;
    int restored = prev > 0 ? prev : 1;
    await prefs.setInt(_keyStreak, restored);
    await prefs.setString(_keyLastDate, today);
    return restored;
  }


  String _getTodayString() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }
}
