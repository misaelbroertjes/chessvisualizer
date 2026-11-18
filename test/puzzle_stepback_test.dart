import 'dart:convert';
import 'dart:io';
import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chess_visualization_app/models/puzzle.dart';
import 'package:chess_visualization_app/utils/chess_move_helper.dart';
import 'package:chess_visualization_app/widgets/puzzle_share_sheet.dart';

bool _applyMove(chess_lib.Chess game, String moveStr) {
  if (moveStr.length >= 4 && RegExp(r'^[a-h][1-8][a-h][1-8]').hasMatch(moveStr)) {
    final moveMap = <String, String>{
      'from': moveStr.substring(0, 2),
      'to': moveStr.substring(2, 4),
    };
    if (moveStr.length >= 5) {
      moveMap['promotion'] = moveStr.substring(4, 5).toLowerCase();
    }
    return game.move(moveMap);
  }
  return game.move(moveStr);
}

void main() {
  test('Puzzle.pliesBeforeFen handles both exact and off-by-1 ply values', () {
    final pWhite = Puzzle(
      id: '05oKL',
      fen: '8/8/3k1p2/6p1/2pbP1P1/8/1pK5/5R2 w - - 0 59',
      solution: const ['f1d1', 'd6e5', 'd1f1', 'e5e4'],
      rating: 1664,
      themes: const [],
      gameId: 'GkZm7Zaj',
      ply: 117, // intentionally off-by-1
      preMoves: const [],
      forcingScore: 0,
      gameMoves: const [],
    );
    expect(pWhite.pliesBeforeFen, 116);

    final pBlack = Puzzle(
      id: 'testBlack',
      fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
      solution: const ['e7e5'],
      rating: 1200,
      themes: const [],
      gameId: 'x',
      ply: 2, // intentionally off-by-1
      preMoves: const [],
      forcingScore: 0,
      gameMoves: const [],
    );
    expect(pBlack.pliesBeforeFen, 1);
  });

  test('All 3000 puzzles in puzzles.json align ply/preMoves with FEN and blunder', () {
    final raw = File('assets/data/puzzles.json').readAsStringSync();
    final List<dynamic> decoded = json.decode(raw) as List<dynamic>;
    final puzzles = decoded
        .map((e) => Puzzle.fromJson(e as Map<String, dynamic>))
        .toList();

    expect(puzzles.length, 3000);

    // Check Puzzle 05oKL (the bug report puzzle) specifically at Depth 4
    final bugPuzzle = puzzles.firstWhere((p) => p.id == '05oKL');
    expect(bugPuzzle.ply, 116);
    expect(bugPuzzle.pliesBeforeFen, 116);
    // Setup moves at depth 4 (3 setup moves before blunder): Kd6, Kc2, c4
    expect(
      bugPuzzle.gameMoves.sublist(bugPuzzle.pliesBeforeFen - 3, bugPuzzle.pliesBeforeFen),
      ['Kd6', 'Kc2', 'c4'],
    );
    expect(bugPuzzle.preMoves.last, 'c4');

    // Verify full alignment across all 3000 puzzles
    for (final p in puzzles) {
      expect(
        p.ply,
        p.pliesBeforeFen,
        reason: 'Puzzle ${p.id} has ply=${p.ply} but FEN has ${p.pliesBeforeFen} plies before it',
      );
      expect(
        p.gameMoves.length,
        greaterThanOrEqualTo(p.pliesBeforeFen),
        reason: 'Puzzle ${p.id} gameMoves shorter than pliesBeforeFen',
      );
      if (p.preMoves.isNotEmpty && p.pliesBeforeFen > 0) {
        expect(
          p.preMoves.last,
          p.gameMoves[p.pliesBeforeFen - 1],
          reason: 'Puzzle ${p.id} last preMove should match gameMoves[pliesBeforeFen - 1]',
        );
      }
    }

    // Replay a representative sample spanning both batches (0..999 and 1000..2999) + 05oKL
    final sampleIndices = <int>[
      0, 1, 500, 999,
      1000, 1001, 1500, 2000, 2500, 2999,
      puzzles.indexWhere((p) => p.id == '05oKL'),
    ];
    for (final idx in sampleIndices) {
      final p = puzzles[idx];
      final game = chess_lib.Chess();
      for (int i = 0; i < p.pliesBeforeFen; i++) {
        expect(
          _applyMove(game, p.gameMoves[i]),
          isTrue,
          reason: 'Puzzle ${p.id} failed replaying move $i (${p.gameMoves[i]})',
        );
      }
      // Board + side-to-move must match puzzle.fen
      final replayedFenParts = game.generate_fen().split(' ');
      final expectedFenParts = p.fen.split(' ');
      expect(replayedFenParts[0], expectedFenParts[0], reason: 'Board mismatch for ${p.id}');
      expect(replayedFenParts[1], expectedFenParts[1], reason: 'Side-to-move mismatch for ${p.id}');

      // Blunder (solution[0]) must be legal from the replayed position and have a piece on 'from'
      final blunder = p.solution.first;
      expect(
        game.get(blunder.substring(0, 2)),
        isNotNull,
        reason: 'Blunder origin square empty for ${p.id} ($blunder)',
      );
      expect(
        _applyMove(game, blunder),
        isTrue,
        reason: 'Blunder $blunder illegal for ${p.id}',
      );
    }
  });

  test('ChessMoveHelper.findCheckmateMove accepts any legal mate-in-1', () {
    // Classic position with TWO mate-in-1s for White: Qa8# and Qb7# (and Rd8#)
    // Black king on g8, pawns f7/g7/h7, White rooks on a1 & d1 -> Ra8# and Rd8#
    final game = chess_lib.Chess.fromFEN('6k1/5ppp/8/8/8/8/8/R2R2K1 w - - 0 1');

    expect(ChessMoveHelper.findCheckmateMove(game, 'a1', 'a8'), 'a1a8');
    expect(ChessMoveHelper.findCheckmateMove(game, 'd1', 'd8'), 'd1d8');
    // Legal non-mate move must return null
    expect(ChessMoveHelper.findCheckmateMove(game, 'a1', 'a7'), isNull);
    // Illegal move must return null
    expect(ChessMoveHelper.findCheckmateMove(game, 'a1', 'h8'), isNull);
    // Original game state must remain untouched
    expect(game.get('a1'), isNotNull);
    expect(game.get('d1'), isNotNull);
  });

  test('ChessMoveHelper.findCheckmateMove handles promotion, underpromotion, and Stepback origins', () {
    // White pawn on c7 promotes to Queen on c8 for mate
    final queenPromoGame = chess_lib.Chess.fromFEN('6k1/2P2ppp/8/8/8/8/8/6K1 w - - 0 1');
    expect(ChessMoveHelper.findCheckmateMove(queenPromoGame, 'c7', 'c8'), 'c7c8q');

    // Only underpromotion to Knight (f7f8n) delivers smothered mate; f7f8q is not even check
    final knightPromoGame = chess_lib.Chess.fromFEN('6br/5Prk/6pp/8/8/8/8/6K1 w - - 0 1');
    expect(ChessMoveHelper.findCheckmateMove(knightPromoGame, 'f7', 'f8'), 'f7f8n');

    // Stepback Step 1: tapping either the mental square (d1) or its original visible square (e1)
    final gameWithOrigin = chess_lib.Chess.fromFEN('6k1/5ppp/8/8/8/8/8/R2R2K1 w - - 0 1');
    final origins = {'d1': 'e1', 'a1': 'a1'};
    expect(
      ChessMoveHelper.findCheckmateMoveWithOrigins(gameWithOrigin, 'e1', 'd8', origins),
      'd1d8',
    );
    expect(
      ChessMoveHelper.findCheckmateMoveWithOrigins(gameWithOrigin, 'd1', 'd8', origins),
      'd1d8',
    );
  });

  test('PuzzleShareData builds valid Lichess Analysis URL and non-spoiler share text', () {
    const data = PuzzleShareData(
      puzzleId: '05oKL',
      rating: 1664,
      modeTitle: 'Puzzle Stepback',
      depthLabel: '4 Moves',
      playerColor: 'black',
      boardPosition: {'d6': 'bK', 'c2': 'wK', 'd1': 'wR'},
      fen: '8/8/3k1p2/6p1/2pbP1P1/8/1pK5/3R4 b - - 1 59',
      movesToCalculate: [
        {'moveNo': '1', 'move': 'Kd6', 'chessNotation': '57... Kd6'},
        {'moveNo': '2', 'move': 'Kc2', 'chessNotation': '58. Kc2'},
        {'moveNo': '3', 'move': 'c4', 'chessNotation': '58... c4'},
        {'moveNo': '4', 'move': 'Rd1', 'chessNotation': '59. Rd1'},
      ],
    );

    expect(
      data.lichessAnalysisUri.toString(),
      'https://lichess.org/analysis/8/8/3k1p2/6p1/2pbP1P1/8/1pK5/3R4_b_-_-_1_59?color=black',
    );
    final shareText = data.buildShareText();
    expect(shareText, contains('Puzzle #05oKL'));
    expect(shareText, contains('Black to move'));
    expect(shareText, contains('59. Rd1'));
    expect(shareText, contains('FEN: 8/8/3k1p2/6p1/2pbP1P1/8/1pK5/3R4 b - - 1 59'));
    // Solution (Ke5 / d6e5) must not be leaked
    expect(shareText, isNot(contains('Ke5')));
  });

  testWidgets('PuzzleShareSheet renders preview card and all 3 actions', (tester) async {
    const data = PuzzleShareData(
      puzzleId: '05oKL',
      rating: 1664,
      modeTitle: 'Puzzle Stepback',
      depthLabel: '4 Moves',
      playerColor: 'black',
      boardPosition: {},
      fen: '8/8/3k1p2/6p1/2pbP1P1/8/1pK5/3R4 b - - 1 59',
      movesToCalculate: [
        {'moveNo': '1', 'move': 'Kd6', 'chessNotation': '57... Kd6'},
        {'moveNo': '2', 'move': 'Rd1', 'chessNotation': '59. Rd1'},
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PuzzleShareSheet(data: data),
        ),
      ),
    );

    expect(find.text('Share as Image'), findsOneWidget);
    expect(find.text('Lichess Analysis'), findsOneWidget);
    expect(find.text('Copy FEN / ID'), findsOneWidget);
    expect(find.text('Puzzle #05oKL • Rating 1664'), findsOneWidget);
    expect(find.text('Black to move'), findsOneWidget);
  });

  test('ChessMoveHelper.getLegalDestinations respects pins, checks, and castling', () {
    // Standard start position: e2 pawn can go to e3/e4, b1 knight to a3/c3, opponent piece empty
    final start = chess_lib.Chess();
    expect(ChessMoveHelper.getLegalDestinations(start, 'e2'), {'e3', 'e4'});
    expect(ChessMoveHelper.getLegalDestinations(start, 'b1'), {'a3', 'c3'});
    expect(ChessMoveHelper.getLegalDestinations(start, 'e7'), isEmpty);
    expect(ChessMoveHelper.getLegalDestinations(start, 'e4'), isEmpty);

    // Pinned knight on e2 cannot move at all (Black rook on e8 pins it to White king on e1)
    final pinned = chess_lib.Chess.fromFEN('4r1k1/8/8/8/8/8/4N3/4K3 w - - 0 1');
    expect(ChessMoveHelper.getLegalDestinations(pinned, 'e2'), isEmpty);

    // Castling available: White king on e1 can go to g1 (O-O) as well as d1/d2/e2/f1/f2
    final castle = chess_lib.Chess.fromFEN('4k3/8/8/8/8/8/8/4K2R w K - 0 1');
    expect(ChessMoveHelper.getLegalDestinations(castle, 'e1'), contains('g1'));
  });
}
