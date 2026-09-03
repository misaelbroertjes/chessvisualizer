class Puzzle {
  final String id;
  final String fen;
  final List<String> solution;
  final int rating;
  final List<String> themes;
  final String gameId;
  final int ply;
  final List<String> preMoves;
  final int forcingScore;
  final List<String> gameMoves;

  Puzzle({
    required this.id,
    required this.fen,
    required this.solution,
    required this.rating,
    required this.themes,
    required this.gameId,
    required this.ply,
    required this.preMoves,
    required this.forcingScore,
    required this.gameMoves,
  });

  factory Puzzle.fromJson(Map<String, dynamic> json) {
    return Puzzle(
      id: json['id'] as String? ?? '',
      fen: json['fen'] as String? ?? '',
      solution: (json['solution'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      rating: (json['rating'] as num?)?.toInt() ?? 1500,
      themes: (json['themes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      gameId: json['gameId'] as String? ?? '',
      ply: (json['ply'] as num?)?.toInt() ?? 0,
      preMoves: (json['preMoves'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      forcingScore: (json['forcingScore'] as num?)?.toInt() ?? 0,
      gameMoves: (json['gameMoves'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}
