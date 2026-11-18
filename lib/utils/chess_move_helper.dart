import 'package:chess/chess.dart' as chess_lib;

class ChessMoveHelper {
  static final RegExp _uciPattern = RegExp(r'^[a-h][1-8][a-h][1-8]');

  /// Applies a move in either UCI (e.g. "e2e4", "e7e8q") or SAN (e.g. "Nf3") format.
  static bool applyMove(chess_lib.Chess game, String moveStr) {
    if (moveStr.isEmpty) return false;
    try {
      if (moveStr.length >= 4 && _uciPattern.hasMatch(moveStr)) {
        final moveMap = <String, String>{
          'from': moveStr.substring(0, 2),
          'to': moveStr.substring(2, 4),
        };
        if (moveStr.length >= 5) {
          moveMap['promotion'] = moveStr.substring(4, 5).toLowerCase();
        }
        return game.move(moveMap);
      } else {
        return game.move(moveStr);
      }
    } catch (_) {
      return false;
    }
  }

  /// Checks whether moving from [from] to [to] in [game] is a legal move that
  /// delivers immediate checkmate.
  ///
  /// For pawn moves reaching rank 1 or 8, all promotion pieces (q, r, n, b) are
  /// tested so that promotion checkmates (including underpromotions) are accepted.
  /// Returns the UCI move string (e.g. "d1h5" or "e7e8q") if it delivers checkmate,
  /// or `null` otherwise. Does not mutate [game].
  static String? findCheckmateMove(chess_lib.Chess game, String from, String to) {
    if (from.length != 2 || to.length != 2 || from == to) return null;

    final piece = game.get(from);
    if (piece == null || piece.color != game.turn) return null;

    final fen = game.generate_fen();
    final isPromotionRank =
        piece.type == chess_lib.PieceType.PAWN && (to[1] == '1' || to[1] == '8');

    if (isPromotionRank) {
      for (final promo in const ['q', 'r', 'n', 'b']) {
        final probe = chess_lib.Chess.fromFEN(fen);
        final ok = probe.move({'from': from, 'to': to, 'promotion': promo});
        if (ok && probe.in_checkmate) {
          return '$from$to$promo';
        }
      }
      return null;
    }

    final probe = chess_lib.Chess.fromFEN(fen);
    final ok = probe.move({'from': from, 'to': to});
    if (ok && probe.in_checkmate) {
      return '$from$to';
    }
    return null;
  }

  /// Variant of [findCheckmateMove] for Stepback Step 1, where a player may tap
  /// either the piece's current mental square OR its original visible square on
  /// the stepback board (tracked via [originOfMentalSquare], mapping
  /// `mentalSquare -> visibleOriginSquare`).
  static String? findCheckmateMoveWithOrigins(
    chess_lib.Chess game,
    String tappedFrom,
    String tappedTo,
    Map<String, String> originOfMentalSquare,
  ) {
    final direct = findCheckmateMove(game, tappedFrom, tappedTo);
    if (direct != null) return direct;

    for (final entry in originOfMentalSquare.entries) {
      if (entry.value == tappedFrom) {
        final viaOrigin = findCheckmateMove(game, entry.key, tappedTo);
        if (viaOrigin != null) return viaOrigin;
      }
    }
    return null;
  }

  /// Returns all strictly legal destination squares (e.g. `{'e4', 'e3'}`) for
  /// the piece standing on [fromSquare]. Returns an empty set if [fromSquare]
  /// is empty, belongs to the opponent, or has no legal moves.
  static Set<String> getLegalDestinations(chess_lib.Chess game, String fromSquare) {
    if (fromSquare.length != 2) return const {};
    final piece = game.get(fromSquare);
    if (piece == null || piece.color != game.turn) return const {};

    final moves = game.generate_moves({'square': fromSquare});
    return {
      for (final m in moves) m.toAlgebraic,
    };
  }
}
