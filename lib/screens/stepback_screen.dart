import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess_lib;
import '../models/puzzle.dart';
import '../services/puzzle_service.dart';
import '../services/storage_service.dart';
import '../services/audio_service.dart';
import '../widgets/chessboard_widget.dart';

import '../widgets/energy_dialog.dart';

import '../widgets/mode_info_dialog.dart';

class StepbackScreen extends StatefulWidget {
  const StepbackScreen({super.key});

  @override
  State<StepbackScreen> createState() => _StepbackScreenState();
}


class _StepbackScreenState extends State<StepbackScreen> {
  final PuzzleService _puzzleService = PuzzleService();
  final StorageService _storageService = StorageService();
  final AudioService _audioService = AudioService();
  final ScrollController _scrollController = ScrollController();

  Puzzle? _currentPuzzle;
  int _visualizationDepth = 1; // 1, 2, 3, 4, or 5 moves in head
  bool _visualAid = false;
  String _gameState = 'solving'; // 'solving', 'feedback'

  Map<String, String> _boardPosition = {};
  late chess_lib.Chess _activeGame;
  String _playerColor = 'white';
  List<String> _solutionMoves = [];
  int _stepIndex = 1;
  final List<Map<String, String>> _movesTable = [];
  
  Set<String> _selectedSquares = {};
  Set<String> _greenHighlights = {};
  Set<String> _errorSquares = {};
  final Set<String> _pieceMarkers = {};

  // Replay Navigation
  final List<Map<String, dynamic>> _historyStates = [];
  int _historyIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadNewPuzzle();
    _checkFirstTimeInfo();
  }

  void _checkFirstTimeInfo() async {
    final seen = await _storageService.hasSeenModeInfo('stepback');
    if (!seen && mounted) {
      await _storageService.setSeenModeInfo('stepback');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ModeInfoDialog.showStepbackInfo(context);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadNewPuzzle() {
    setState(() {
      _gameState = 'solving';
      _selectedSquares.clear();
      _greenHighlights.clear();
      _errorSquares.clear();
      _pieceMarkers.clear();
      _historyStates.clear();
      _historyIndex = 0;
    });

    final puzzle = _puzzleService.getRandomPuzzle(
      forcingOnly: true,
      minRating: 1300,
      minPreMoves: _visualizationDepth - 1,
    );

    if (puzzle == null) return;

    _currentPuzzle = puzzle;
    _solutionMoves = List.from(puzzle.solution);
    _stepIndex = 1;

    // Determine player color from FEN
    final fenParts = puzzle.fen.split(' ');
    final blunderColor = fenParts[1];
    _playerColor = blunderColor == 'w' ? 'black' : 'white';

    _setupStepbackPosition();
  }

  String _formatSAN(chess_lib.Chess game, String moveStr) {
    if (moveStr.isEmpty) return moveStr;
    // If moveStr is already SAN (like "Nf3", "O-O", "e4", "Bxc5"), return it directly
    if (!RegExp(r'^[a-h][1-8][a-h][1-8]').hasMatch(moveStr)) {
      return moveStr;
    }

    final from = moveStr.substring(0, 2);
    final to = moveStr.substring(2, 4);

    final piece = game.get(from);
    if (piece == null) return moveStr;

    final type = piece.type.name.toUpperCase();

    // Castling
    if (type == 'K') {
      if ((from == 'e1' && to == 'g1') || (from == 'e8' && to == 'g8')) return 'O-O';
      if ((from == 'e1' && to == 'c1') || (from == 'e8' && to == 'c8')) return 'O-O-O';
    }

    final isCapture = game.get(to) != null;
    final captureChar = isCapture ? 'x' : '';

    if (type == 'P') {
      if (isCapture) {
        return '${from[0]}x$to';
      }
      return to;
    }

    return '$type$captureChar$to';
  }

  bool _makeMove(chess_lib.Chess game, String moveStr) {
    if (moveStr.isEmpty) return false;
    try {
      if (moveStr.length >= 4 && RegExp(r'^[a-h][1-8][a-h][1-8]').hasMatch(moveStr)) {
        return game.move({'from': moveStr.substring(0, 2), 'to': moveStr.substring(2, 4)});
      } else {
        return game.move(moveStr);
      }
    } catch (_) {
      return false;
    }
  }

  void _setupStepbackPosition() {
    if (_currentPuzzle == null) return;
    final puzzle = _currentPuzzle!;

    _movesTable.clear();
    _pieceMarkers.clear();

    final int targetHeadMoves = _visualizationDepth; // e.g., 1, 2, 3, 4, 5
    final int preMovesNeeded = targetHeadMoves - 1; // e.g., 0, 1, 2, 3, 4

    final int totalPly = puzzle.ply;
    final List<String> gameMoves = puzzle.gameMoves;

    int startPly = totalPly - preMovesNeeded;
    if (startPly < 0) startPly = 0;

    // Simulate game from standard start position up to startPly
    final tempGame = chess_lib.Chess();
    if (gameMoves.isNotEmpty && gameMoves.length >= startPly && startPly > 0) {
      for (int i = 0; i < startPly; i++) {
        _makeMove(tempGame, gameMoves[i]);
      }
    } else {
      // Fallback: start at puzzle FEN if gameMoves unavailable
      tempGame.load(puzzle.fen);
    }

    _activeGame = tempGame;
    _boardPosition = _getChessboardMap(_activeGame);

    // Track move simulation state to generate SAN labels for movesTable
    final simGame = chess_lib.Chess.fromFEN(_activeGame.generate_fen());
    int moveNo = 1;

    // 1. Add setup pre-moves
    if (gameMoves.isNotEmpty && gameMoves.length >= totalPly) {
      for (int i = startPly; i < totalPly; i++) {
        final m = gameMoves[i];
        final sanMove = _formatSAN(simGame, m);
        _makeMove(simGame, m);

        _movesTable.add({
          'moveNo': '$moveNo',
          'move': sanMove,
          'label': 'Setup Move (in head)'
        });
        moveNo++;
      }
    } else if (puzzle.preMoves.isNotEmpty) {
      final preMoves = puzzle.preMoves;
      int takePreMoves = preMoves.length >= preMovesNeeded ? preMovesNeeded : preMoves.length;
      for (int i = 0; i < takePreMoves; i++) {
        final pm = preMoves[preMoves.length - takePreMoves + i];
        final sanPM = _formatSAN(simGame, pm);
        _makeMove(simGame, pm);

        _movesTable.add({
          'moveNo': '$moveNo',
          'move': sanPM,
          'label': 'Setup Move (in head)'
        });
        moveNo++;
      }
    }

    // 2. Add the Opponent Blunder move (solutionMoves[0])
    if (_solutionMoves.isNotEmpty) {
      final blunder = _solutionMoves[0];
      final sanBlunder = _formatSAN(simGame, blunder);
      _makeMove(simGame, blunder);

      _movesTable.add({
        'moveNo': '$moveNo',
        'move': sanBlunder,
        'label': 'Opponent Move (in head)'
      });
    }

    setState(() {});
  }


  Map<String, String> _getChessboardMap(chess_lib.Chess game) {
    final Map<String, String> pos = {};
    final files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
    final ranks = ['1', '2', '3', '4', '5', '6', '7', '8'];

    for (var r in ranks) {
      for (var f in files) {
        final sq = '$f$r';
        final piece = game.get(sq);
        if (piece != null) {
          final colorPrefix = piece.color == chess_lib.Color.WHITE ? 'w' : 'b';
          final typeUpper = piece.type.name.toUpperCase();
          pos[sq] = '$colorPrefix$typeUpper';
        }
      }
    }
    return pos;
  }

  void _handleSquareTap(String square) {
    if (_gameState != 'solving') return;

    if (_selectedSquares.isEmpty) {
      // Select piece
      if (_boardPosition.containsKey(square)) {
        setState(() {
          _selectedSquares = {square};
        });
      }
    } else {
      final from = _selectedSquares.first;
      final to = square;
      _selectedSquares.clear();

      final moveUCI = '$from$to';
      final expectedMove = _solutionMoves[_stepIndex];
      final expectedFrom = expectedMove.length >= 4 ? expectedMove.substring(0, 2) : '';
      final expectedTo = expectedMove.length >= 4 ? expectedMove.substring(2, 4) : '';

      final selectedPiece = _boardPosition[from];
      final expectedPiece = _currentPuzzle != null ? chess_lib.Chess.fromFEN(_currentPuzzle!.fen).get(expectedFrom) : null;
      final expectedPieceType = expectedPiece != null ? '${expectedPiece.color == chess_lib.Color.WHITE ? "w" : "b"}${expectedPiece.type.name.toUpperCase()}' : '';

      bool isCorrect = (moveUCI == expectedMove || expectedMove.startsWith(moveUCI)) ||
                       (to == expectedTo && selectedPiece != null && selectedPiece == expectedPieceType);

      if (isCorrect) {
        // Correct move!
        _audioService.playMove();

        final fenGame = chess_lib.Chess.fromFEN(_currentPuzzle!.fen);
        if (_solutionMoves.isNotEmpty) {
          fenGame.move({'from': _solutionMoves[0].substring(0, 2), 'to': _solutionMoves[0].substring(2, 4)});
        }
        fenGame.move({'from': expectedFrom, 'to': expectedTo});

        _activeGame = fenGame;
        _boardPosition = _getChessboardMap(_activeGame);

        setState(() {
          _greenHighlights = {expectedFrom, expectedTo};
          _gameState = 'feedback';
        });

        _storageService.recordActivity(true);
        _audioService.playSuccess();
        _buildHistoryReplay();

        // Smoothly auto-scroll to bottom to reveal feedback & next button
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        // Incorrect move: costs 1 energy!
        _audioService.playError();
        setState(() {
          _errorSquares = {from, to};
        });

        _storageService.consumeEnergy().then((hasEnergy) {
          if (!hasEnergy && mounted) {
            EnergyDialog.show(context, onRefilled: () {});
          }
        });

        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            setState(() {
              _errorSquares.clear();
            });
          }
        });
      }
    }
  }

  void _buildHistoryReplay() {
    _historyStates.clear();
    if (_currentPuzzle == null) return;

    final game = chess_lib.Chess.fromFEN(_currentPuzzle!.fen);
    _historyStates.add({
      'position': _getChessboardMap(game),
      'label': 'Start Position',
    });

    for (int i = 0; i < _solutionMoves.length; i++) {
      final move = _solutionMoves[i];
      game.move({'from': move.substring(0, 2), 'to': move.substring(2, 4)});
      _historyStates.add({
        'position': _getChessboardMap(game),
        'label': i == 0 ? 'Blunder' : (i % 2 == 1 ? 'Your Move' : 'Response'),
      });
    }

    _historyIndex = _historyStates.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text(
          'Puzzle Stepback',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Color(0xFF38BDF8)),
            tooltip: 'How to Play',
            onPressed: () => ModeInfoDialog.showStepbackInfo(context),
          ),
          Tooltip(
            message: 'Toggle Visual Aid Ghost Dots',
            child: IconButton(
              icon: Icon(
                _visualAid ? Icons.visibility : Icons.visibility_off,
                color: _visualAid ? const Color(0xFF38BDF8) : Colors.grey,
              ),
              onPressed: () {
                setState(() {
                  _visualAid = !_visualAid;
                });
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _gameState == 'feedback'
          ? Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1E293B),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.arrow_forward, color: Colors.white),
                    label: const Text(
                      'Next Puzzle',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    onPressed: _loadNewPuzzle,
                  ),
                ),
              ),
            )
          : null,
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Settings bar: Visualization Depth selector
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Visualization Depth:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  DropdownButton<int>(
                    value: _visualizationDepth,
                    dropdownColor: const Color(0xFF1E293B),
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 Move in Head', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                      DropdownMenuItem(value: 2, child: Text('2 Moves in Head', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                      DropdownMenuItem(value: 3, child: Text('3 Moves in Head', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                      DropdownMenuItem(value: 4, child: Text('4 Moves in Head', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                      DropdownMenuItem(value: 5, child: Text('5 Moves in Head', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                    ],
                    onChanged: (val) {
                      if (val != null && val != _visualizationDepth) {
                        setState(() {
                          _visualizationDepth = val;
                        });
                        _loadNewPuzzle(); // Loads puzzle for new depth without consuming energy
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Chessboard
            ChessboardWidget(
              position: _gameState == 'feedback' && _historyStates.isNotEmpty
                  ? _historyStates[_historyIndex]['position'] as Map<String, String>
                  : _boardPosition,
              orientation: _playerColor,
              selectedSquares: _selectedSquares,
              greenHighlights: _greenHighlights,
              errorSquares: _errorSquares,
              pieceMarkers: _visualAid ? _pieceMarkers : const {},
              onSquareTap: _handleSquareTap,
            ),

            const SizedBox(height: 16),

            // Permanent Moves Table (Always Visible)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.psychology, color: Color(0xFF38BDF8), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Moves to Calculate in Your Head:',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_movesTable.isEmpty)
                    const Text('Calculate the moves in your head and solve on the board!', style: TextStyle(color: Colors.grey))
                  else
                    ..._movesTable.map((row) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Text(
                                '${row['moveNo']}.',
                                style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  row['move'] ?? '',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                               ),
                              const SizedBox(width: 12),
                              Text(
                                '${row['label']}',
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        )),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (_gameState == 'solving') ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6366F1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your turn! Find and play the winning move on the board for $_playerColor!',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_gameState == 'feedback') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  border: Border.all(color: const Color(0xFF10B981)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.stars, color: Color(0xFF10B981), size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Well done! Puzzle Solved!',
                      style: TextStyle(color: Color(0xFF10B981), fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Replay Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _historyIndex = 0;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_left, color: Colors.white, size: 36),
                    onPressed: () {
                      if (_historyIndex > 0) {
                        setState(() {
                          _historyIndex--;
                        });
                      }
                    },
                  ),
                  Text(
                    'Step ${_historyIndex + 1}/${_historyStates.length}',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_right, color: Colors.white, size: 36),
                    onPressed: () {
                      if (_historyIndex < _historyStates.length - 1) {
                        setState(() {
                          _historyIndex++;
                        });
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _historyIndex = _historyStates.length - 1;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.arrow_forward, color: Colors.white),
                  label: const Text(
                    'Next Puzzle',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  onPressed: _loadNewPuzzle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}



