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
  String _gameState = 'solving'; // 'solving', 'opponent_moving', 'feedback'

  Map<String, String> _boardPosition = {};
  Map<String, String> _stepbackStartPosition = {};
  late chess_lib.Chess _activeGame;
  String _playerColor = 'white';
  List<String> _solutionMoves = [];
  int _stepIndex = 1;
  final List<Map<String, String>> _movesTable = [];
  final List<Map<String, dynamic>> _setupReplaySteps = [];
  String? _originSquareOfFirstMove;
  bool _recordedMistakeForCurrentPuzzle = false;

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

  Future<void> _loadNewPuzzle() async {
    final stats = await _storageService.loadUserStats();
    if (!mounted) return;

    setState(() {
      _gameState = 'solving';
      _selectedSquares.clear();
      _greenHighlights.clear();
      _errorSquares.clear();
      _pieceMarkers.clear();
      _historyStates.clear();
      _setupReplaySteps.clear();
      _historyIndex = 0;
      _originSquareOfFirstMove = null;
      _recordedMistakeForCurrentPuzzle = false;
    });

    final minRating = (stats.eloRating - 350).clamp(800, 2200);
    final maxRating = (stats.eloRating + 450).clamp(1300, 2800);

    final puzzle = _puzzleService.getRandomPuzzle(
      forcingOnly: true,
      minRating: minRating,
      maxRating: maxRating,
      minPreMoves: _visualizationDepth - 1,
    );

    if (puzzle == null) return;

    _currentPuzzle = puzzle;
    _solutionMoves = List.from(puzzle.solution);
    _stepIndex = 1;

    // Determine player color from FEN
    final fenParts = puzzle.fen.split(' ');
    final blunderColor = fenParts.length > 1 ? fenParts[1] : 'w';
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
    final promo = moveStr.length >= 5 ? '=${moveStr.substring(4, 5).toUpperCase()}' : '';

    final piece = game.get(from);
    if (piece == null) return moveStr;

    final type = piece.type.name.toUpperCase();

    // Castling
    if (type == 'K') {
      if ((from == 'e1' && to == 'g1') || (from == 'e8' && to == 'g8')) return 'O-O';
      if ((from == 'e1' && to == 'c1') || (from == 'e8' && to == 'c8')) return 'O-O-O';
    }

    final isEnPassant = type == 'P' && from[0] != to[0] && game.get(to) == null;
    final isCapture = game.get(to) != null || isEnPassant;
    final captureChar = isCapture ? 'x' : '';

    if (type == 'P') {
      if (isCapture) {
        return '${from[0]}x$to$promo';
      }
      return '$to$promo';
    }

    return '$type$captureChar$to$promo';
  }

  bool _makeMove(chess_lib.Chess game, String moveStr) {
    if (moveStr.isEmpty) return false;
    try {
      if (moveStr.length >= 4 && RegExp(r'^[a-h][1-8][a-h][1-8]').hasMatch(moveStr)) {
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

  void _recordMentalStepOnSim(
    chess_lib.Chess simGame,
    String moveStr,
    Map<String, String> originOfSquare,
    String stepLabel,
  ) {
    final beforeMap = _getChessboardMap(simGame);
    final turnPrefix = simGame.turn == chess_lib.Color.WHITE ? 'w' : 'b';
    final san = _formatSAN(simGame, moveStr);
    final moved = _makeMove(simGame, moveStr);
    if (!moved) return;
    final afterMap = _getChessboardMap(simGame);

    String? fromSq;
    String? toSq;

    if (RegExp(r'^[a-h][1-8][a-h][1-8]').hasMatch(moveStr)) {
      fromSq = moveStr.substring(0, 2);
      toSq = moveStr.substring(2, 4);
    } else if (san.startsWith('O-O')) {
      final rank = turnPrefix == 'w' ? '1' : '8';
      fromSq = 'e$rank';
      toSq = san.startsWith('O-O-O') ? 'c$rank' : 'g$rank';
    } else {
      for (final sq in beforeMap.keys) {
        if (beforeMap[sq]!.startsWith(turnPrefix) && !afterMap.containsKey(sq)) {
          fromSq = sq;
          break;
        }
      }
      for (final sq in afterMap.keys) {
        if (afterMap[sq]!.startsWith(turnPrefix) && beforeMap[sq] != afterMap[sq]) {
          toSq = sq;
          break;
        }
      }
    }

    if (fromSq != null) _pieceMarkers.add(fromSq);
    if (toSq != null) _pieceMarkers.add(toSq);

    if (fromSq != null && toSq != null) {
      final origin = originOfSquare.remove(fromSq) ?? fromSq;
      originOfSquare[toSq] = origin;
    }

    _setupReplaySteps.add({
      'position': afterMap,
      'label': '$stepLabel ($san)',
    });
  }

  void _setupStepbackPosition() {
    if (_currentPuzzle == null) return;
    final puzzle = _currentPuzzle!;

    _movesTable.clear();
    _pieceMarkers.clear();
    _setupReplaySteps.clear();

    final int targetHeadMoves = _visualizationDepth; // e.g., 1, 2, 3, 4, 5
    final int preMovesNeeded = targetHeadMoves - 1; // e.g., 0, 1, 2, 3, 4

    final int totalPly = puzzle.ply;
    final List<String> gameMoves = puzzle.gameMoves;

    int startPly = totalPly - preMovesNeeded;
    if (startPly < 0) startPly = 0;

    // Simulate game from standard start position up to startPly
    final tempGame = chess_lib.Chess();
    if (preMovesNeeded == 0) {
      tempGame.load(puzzle.fen);
    } else if (gameMoves.isNotEmpty && gameMoves.length >= totalPly) {
      for (int i = 0; i < startPly; i++) {
        _makeMove(tempGame, gameMoves[i]);
      }
    } else {
      tempGame.load(puzzle.fen);
    }

    _activeGame = tempGame;
    _boardPosition = _getChessboardMap(_activeGame);
    _stepbackStartPosition = Map<String, String>.from(_boardPosition);

    final Map<String, String> originOfSquare = {
      for (final sq in _boardPosition.keys) sq: sq,
    };

    // Track move simulation state to generate SAN labels for movesTable
    final simGame = chess_lib.Chess.fromFEN(_activeGame.generate_fen());
    int moveNo = 1;

    // 1. Add setup pre-moves
    if (preMovesNeeded > 0 && gameMoves.isNotEmpty && gameMoves.length >= totalPly) {
      for (int i = startPly; i < totalPly; i++) {
        final m = gameMoves[i];
        final sanMove = _formatSAN(simGame, m);
        _recordMentalStepOnSim(simGame, m, originOfSquare, 'Setup Move $moveNo');

        _movesTable.add({
          'moveNo': '$moveNo',
          'move': sanMove,
          'label': 'Setup Move (in head)'
        });
        moveNo++;
      }
    } else if (preMovesNeeded > 0 && puzzle.preMoves.isNotEmpty) {
      final preMoves = puzzle.preMoves;
      int takePreMoves = preMoves.length >= preMovesNeeded ? preMovesNeeded : preMoves.length;
      for (int i = 0; i < takePreMoves; i++) {
        final pm = preMoves[preMoves.length - takePreMoves + i];
        final sanPM = _formatSAN(simGame, pm);
        _recordMentalStepOnSim(simGame, pm, originOfSquare, 'Setup Move $moveNo');

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
      _recordMentalStepOnSim(simGame, blunder, originOfSquare, 'Opponent Move');

      _movesTable.add({
        'moveNo': '$moveNo',
        'move': sanBlunder,
        'label': 'Opponent Move (in head)'
      });
    }

    if (_solutionMoves.length > 1 && _solutionMoves[1].length >= 4) {
      final expectedFrom = _solutionMoves[1].substring(0, 2);
      _originSquareOfFirstMove = originOfSquare[expectedFrom] ?? expectedFrom;
      _pieceMarkers.add(_originSquareOfFirstMove!);
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

  Future<void> _handleSquareTap(String square) async {
    if (_gameState != 'solving' || _currentPuzzle == null) return;
    if (_stepIndex >= _solutionMoves.length) return;

    final expectedMove = _solutionMoves[_stepIndex];
    final expectedFrom = expectedMove.length >= 4 ? expectedMove.substring(0, 2) : '';
    final expectedTo = expectedMove.length >= 4 ? expectedMove.substring(2, 4) : '';

    if (_selectedSquares.isEmpty) {
      // Allow selecting any square with a visible piece OR the mental expectedFrom square
      if (_boardPosition.containsKey(square) || (_stepIndex == 1 && square == expectedFrom)) {
        setState(() {
          _selectedSquares = {square};
        });
      }
      return;
    }

    final from = _selectedSquares.first;
    final to = square;

    // Tapping the same square deselects without costing energy
    if (from == to) {
      setState(() {
        _selectedSquares.clear();
      });
      return;
    }

    // In live board follow-up steps (_stepIndex > 1), tapping another own piece switches selection
    final playerPrefix = _playerColor == 'white' ? 'w' : 'b';
    if (_stepIndex > 1 &&
        _boardPosition[to]?.startsWith(playerPrefix) == true &&
        to != expectedTo) {
      setState(() {
        _selectedSquares = {to};
      });
      return;
    }

    // Ensure the user has energy before evaluating a move attempt
    final currentEnergy = await _storageService.getRemainingEnergy();
    if (!mounted) return;
    if (currentEnergy <= 0) {
      setState(() {
        _selectedSquares.clear();
      });
      EnergyDialog.show(context, onRefilled: () {});
      return;
    }

    _selectedSquares.clear();

    final bool isCorrect = to == expectedTo &&
        (from == expectedFrom ||
            (_stepIndex == 1 && _originSquareOfFirstMove != null && from == _originSquareOfFirstMove));

    if (isCorrect) {
      if (_stepIndex == 1) {
        final fenGame = chess_lib.Chess.fromFEN(_currentPuzzle!.fen);
        if (_solutionMoves.isNotEmpty) {
          _makeMove(fenGame, _solutionMoves[0]);
        }
        final wasCapture = fenGame.get(expectedTo) != null;
        _makeMove(fenGame, expectedMove);
        _activeGame = fenGame;
        _boardPosition = _getChessboardMap(_activeGame);

        if (_activeGame.in_check) {
          _audioService.playCheck();
        } else if (wasCapture) {
          _audioService.playCapture();
        } else {
          _audioService.playMove();
        }
      } else {
        final wasCapture = _activeGame.get(expectedTo) != null;
        _makeMove(_activeGame, expectedMove);
        _boardPosition = _getChessboardMap(_activeGame);

        if (_activeGame.in_check) {
          _audioService.playCheck();
        } else if (wasCapture) {
          _audioService.playCapture();
        } else {
          _audioService.playMove();
        }
      }

      // Check if there is a follow-up opponent response + next player move in the solution
      if (_stepIndex + 2 < _solutionMoves.length) {
        setState(() {
          _greenHighlights = {expectedFrom, expectedTo};
          _gameState = 'opponent_moving';
        });

        final opponentMove = _solutionMoves[_stepIndex + 1];
        final oppFrom = opponentMove.length >= 4 ? opponentMove.substring(0, 2) : '';
        final oppTo = opponentMove.length >= 4 ? opponentMove.substring(2, 4) : '';

        Future.delayed(const Duration(milliseconds: 450), () {
          if (!mounted || _currentPuzzle == null) return;
          final wasCapture = _activeGame.get(oppTo) != null;
          _makeMove(_activeGame, opponentMove);
          _boardPosition = _getChessboardMap(_activeGame);

          if (_activeGame.in_check) {
            _audioService.playCheck();
          } else if (wasCapture) {
            _audioService.playCapture();
          } else {
            _audioService.playMove();
          }

          setState(() {
            _stepIndex += 2;
            _greenHighlights = {oppFrom, oppTo};
            _gameState = 'solving';
          });
        });
      } else {
        // Entire puzzle sequence solved!
        setState(() {
          _greenHighlights = {expectedFrom, expectedTo};
          _gameState = 'feedback';
        });

        _storageService.recordActivity(true);
        _audioService.playSuccess();
        _buildHistoryReplay();

        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } else {
      // Incorrect move: costs 1 energy!
      _audioService.playError();
      if (!_recordedMistakeForCurrentPuzzle) {
        _recordedMistakeForCurrentPuzzle = true;
        _storageService.recordActivity(false, updatePuzzleStats: false);
      }
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

  void _buildHistoryReplay() {
    _historyStates.clear();
    if (_currentPuzzle == null) return;

    _historyStates.add({
      'position': Map<String, String>.from(_stepbackStartPosition),
      'label': 'Stepback Start',
    });

    for (final step in _setupReplaySteps) {
      _historyStates.add({
        'position': Map<String, String>.from(step['position'] as Map<String, String>),
        'label': step['label'] as String,
      });
    }

    final game = chess_lib.Chess.fromFEN(_currentPuzzle!.fen);
    if (_solutionMoves.isNotEmpty) {
      _makeMove(game, _solutionMoves[0]);
    }

    for (int i = 1; i < _solutionMoves.length; i++) {
      final move = _solutionMoves[i];
      final san = _formatSAN(game, move);
      _makeMove(game, move);
      _historyStates.add({
        'position': _getChessboardMap(game),
        'label': i % 2 == 1 ? 'Your Move ($san)' : 'Opponent Reply ($san)',
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
            icon: const Icon(Icons.palette_outlined, color: Color(0xFF38BDF8)),
            tooltip: 'Board Theme',
            onPressed: () => ChessboardWidget.showThemePicker(context),
          ),
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
              pieceMarkers: (_visualAid && _stepIndex == 1 && _gameState == 'solving')
                  ? _pieceMarkers
                  : const {},
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

            if (_gameState == 'solving' || _gameState == 'opponent_moving') ...[
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
                        _stepIndex == 1
                            ? 'Your turn! Find and play the winning move on the board for $_playerColor!'
                            : 'Great first move! Now find the follow-up winning move for $_playerColor!',
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
                  Flexible(
                    child: Column(
                      children: [
                        Text(
                          'Step ${_historyIndex + 1}/${_historyStates.length}',
                          style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                        ),
                        if (_historyStates.isNotEmpty)
                          Text(
                            '${_historyStates[_historyIndex]['label']}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                      ],
                    ),
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
            ],
          ],
        ),
      ),
    );
  }
}



