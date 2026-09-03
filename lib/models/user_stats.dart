class UserStats {
  int streakDays;
  String lastTrainedDate;
  int pathfinderLevel;
  int coordinatesHighScore;
  int totalPuzzlesSolved;
  int totalAttempts;
  int hourlySessionCount;
  String lastSessionHour;
  int eloRating;

  UserStats({
    this.streakDays = 0,
    this.lastTrainedDate = '',
    this.pathfinderLevel = 1,
    this.coordinatesHighScore = 0,
    this.totalPuzzlesSolved = 0,
    this.totalAttempts = 0,
    this.hourlySessionCount = 0,
    this.lastSessionHour = '',
    this.eloRating = 1200,
  });

  double get successRate {
    if (totalAttempts == 0) return 0.0;
    return (totalPuzzlesSolved / totalAttempts) * 100;
  }
}
