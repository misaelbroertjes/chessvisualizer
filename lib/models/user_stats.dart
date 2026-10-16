class UserStats {
  int streakDays;
  String lastTrainedDate;
  int pathfinderLevel;
  int coordinatesHighScore;
  int totalPuzzlesSolved;
  int totalAttempts;
  int eloRating;
  bool canRestoreStreak;

  UserStats({
    this.streakDays = 0,
    this.lastTrainedDate = '',
    this.pathfinderLevel = 1,
    this.coordinatesHighScore = 0,
    this.totalPuzzlesSolved = 0,
    this.totalAttempts = 0,
    this.eloRating = 1200,
    this.canRestoreStreak = false,
  });

  double get successRate {
    if (totalAttempts == 0) return 0.0;
    return (totalPuzzlesSolved / totalAttempts) * 100;
  }
}
