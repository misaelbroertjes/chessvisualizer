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
  int _visualizationDepth = 1; // 1, 2, 3, 4, 5, 7, 10, or 999 (Full Game)
  String _selectedDifficulty = 'auto'; // 'auto', 'easy', 'medium', 'hard', 'master'
  int _userElo = 1200;
  bool _isRatedPuzzle = true;
  int? _lastEloDelta;

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
  bool _solutionWasRevealed = false;

  // Mental Pacer index for deep visualization (6+ moves or Full Game)
  int _mentalPacerIndex = 0;

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

    final isBelowRec =
        PuzzleService.isTierBelowRecommended(_selectedDifficulty, stats.eloRating);
    final filter = PuzzleService.getFilterForTier(_selectedDifficulty, stats.eloRating);

    setState(() {
      _userElo = stats.eloRating;
      _isRatedPuzzle = !isBelowRec;
      _lastEloDelta = null;
      _gameState = 'solving';
      _selectedSquares.clear();
      _greenHighlights.clear();
      _errorSquares.clear();
      _pieceMarkers.clear();
      _historyStates.clear();
      _setupReplaySteps.clear();
      _historyIndex = 0;
      _mentalPacerIndex = 0;
      _originSquareOfFirstMove = null;
      _recordedMistakeForCurrentPuzzle = false;
      _solutionWasRevealed = false;
    });

    final bool isFullGame = _visualizationDepth >= 100;
    final int minPreMoves = isFullGame ? 6 : (_visualizationDepth - 1);
    final int? maxPly = isFullGame ? 30 : null;

    final puzzle = _puzzleService.getRandomPuzzle(
      forcingOnly: filter.forcingOnly,
      minRating: filter.minRating,
      maxRating: filter.maxRating,
      minPreMoves: minPreMoves,
      maxPly: maxPly,
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
    if (!RegExp(r'^[a-h][1-8][a-h][1-8]').hasMatch(moveStr)) {
      return moveStr;
    }

    final from = moveStr.substring(0, 2);
    final to = moveStr.substring(2, 4);
    final promo = moveStr.length >= 5 ? '=${moveStr.substring(4, 5).toUpperCase()}' : '';

    final piece = game.get(from);
    if (piece == null) return moveStr;

    final type = piece.type.name.toUpperCase();

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

    final int totalPly = puzzle.ply;
    final List<String> gameMoves = puzzle.gameMoves;

    final bool isFullGame = _visualizationDepth >= 100;
    final int preMovesNeeded = isFullGame ? totalPly : (_visualizationDepth - 1);

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

    final simGame = chess_lib.Chess.fromFEN(_activeGame.generate_fen());
    int moveNo = 1;

    // 1. Add setup pre-moves
    if (preMovesNeeded > 0 && gameMoves.isNotEmpty && gameMoves.length >= totalPly) {
      for (int i = startPly; i < totalPly; i++) {
        final m = gameMoves[i];
        final isWhiteTurn = simGame.turn == chess_lib.Color.WHITE;
        final chessMoveNum = (i ~/ 2) + 1;
        final sanMove = _formatSAN(simGame, m);
        _recordMentalStepOnSim(simGame, m, originOfSquare, 'Setup Move $moveNo');

        _movesTable.add({
          'moveNo': '$moveNo',
          'chessNotation': isWhiteTurn ? '$chessMoveNum. $sanMove' : '$chessMoveNum... $sanMove',
          'move': sanMove,
          'side': isWhiteTurn ? 'White' : 'Black',
          'label': 'Setup Move (in head)',
        });
        moveNo++;
      }
    } else if (preMovesNeeded > 0 && puzzle.preMoves.isNotEmpty) {
      final preMoves = puzzle.preMoves;
      int takePreMoves = preMoves.length >= preMovesNeeded ? preMovesNeeded : preMoves.length;
      for (int i = 0; i < takePreMoves; i++) {
        final pm = preMoves[preMoves.length - takePreMoves + i];
        final isWhiteTurn = simGame.turn == chess_lib.Color.WHITE;
        final sanPM = _formatSAN(simGame, pm);
        _recordMentalStepOnSim(simGame, pm, originOfSquare, 'Setup Move $moveNo');

        _movesTable.add({
          'moveNo': '$moveNo',
          'chessNotation': sanPM,
          'move': sanPM,
          'side': isWhiteTurn ? 'White' : 'Black',
          'label': 'Setup Move (in head)',
        });
        moveNo++;
      }
    }

    // 2. Add the Opponent Blunder move (solutionMoves[0])
    if (_solutionMoves.isNotEmpty) {
      final blunder = _solutionMoves[0];
      final isWhiteTurn = simGame.turn == chess_lib.Color.WHITE;
      final chessMoveNum = (totalPly ~/ 2) + 1;
      final sanBlunder = _formatSAN(simGame, blunder);
      _recordMentalStepOnSim(simGame, blunder, originOfSquare, 'Opponent Blunder');

      _movesTable.add({
        'moveNo': '$moveNo',
        'chessNotation': isWhiteTurn ? '$chessMoveNum. $sanBlunder' : '$chessMoveNum... $sanBlunder',
        'move': sanBlunder,
        'side': isWhiteTurn ? 'White' : 'Black',
        'label': 'Opponent Blunder (in head)',
      });
    }

    if (_solutionMoves.length > 1 && _solutionMoves[1].length >= 4) {
      final expectedFrom = _solutionMoves[1].substring(0, 2);
      _originSquareOfFirstMove = originOfSquare[expectedFrom] ?? expectedFrom;
      _pieceMarkers.add(_originSquareOfFirstMove!);
    }

    _mentalPacerIndex = 0;
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
    final playerPrefix = _playerColor == 'white' ? 'w' : 'b';

    if (_selectedSquares.isEmpty) {
      // On Step 1 (blindfold/mental position), allow selecting ANY square on the board
      // because the piece in your head may stand on a square that is visibly empty!
      // On follow-up steps (_stepIndex > 1), the board is live so select own pieces.
      if (_stepIndex == 1 || _boardPosition[square]?.startsWith(playerPrefix) == true) {
        setState(() {
          _selectedSquares = {square};
        });
      }
      return;
    }

    final from = _selectedSquares.first;
    final to = square;

    if (from == to) {
      setState(() {
        _selectedSquares.clear();
      });
      return;
    }

    if (_stepIndex > 1 &&
        _boardPosition[to]?.startsWith(playerPrefix) == true &&
        to != expectedTo) {
      setState(() {
        _selectedSquares = {to};
      });
      return;
    }

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
            (_stepIndex == 1 &&
                _originSquareOfFirstMove != null &&
                from == _originSquareOfFirstMove));

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
        if (_isRatedPuzzle && !_recordedMistakeForCurrentPuzzle) {
          final delta = await _storageService.recordRatedPuzzleSuccess(
            puzzleRating: _currentPuzzle!.rating,
            visualizationDepth: _visualizationDepth,
          );
          _lastEloDelta = delta;
          _userElo = (_userElo + delta).clamp(800, 3000);
        } else {
          // Either Unrated mode OR player already made a mistake earlier on this puzzle:
          // Do NOT add ELO back, only award training XP & solved count!
          await _storageService.recordPuzzleCompletionWithoutElo(
            xpEarned: _isRatedPuzzle ? 8 : 10,
            countAttempt: !_recordedMistakeForCurrentPuzzle,
          );
        }

        if (!mounted) return;
        setState(() {
          _greenHighlights = {expectedFrom, expectedTo};
          _gameState = 'feedback';
        });

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
        if (_isRatedPuzzle) {
          _storageService
              .recordRatedPuzzleMistake(
            puzzleRating: _currentPuzzle!.rating,
            visualizationDepth: _visualizationDepth,
          )
              .then((delta) {
            if (mounted) {
              setState(() {
                _lastEloDelta = delta;
                _userElo = (_userElo + delta).clamp(800, 3000);
              });
            }
          });
        }
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

  Future<void> _revealSolution() async {
    if (_gameState != 'solving' || _currentPuzzle == null) return;

    if (!_recordedMistakeForCurrentPuzzle) {
      _recordedMistakeForCurrentPuzzle = true;
      if (_isRatedPuzzle) {
        final delta = await _storageService.recordRatedPuzzleMistake(
          puzzleRating: _currentPuzzle!.rating,
          visualizationDepth: _visualizationDepth,
        );
        if (mounted) {
          _lastEloDelta = delta;
          _userElo = (_userElo + delta).clamp(800, 3000);
        }
      }
      await _storageService.consumeEnergy();
    }

    // Play out the full solution on _activeGame so the user sees the final position
    // and can step through all moves in the Replay Bar.
    final fenGame = chess_lib.Chess.fromFEN(_currentPuzzle!.fen);
    for (final m in _solutionMoves) {
      _makeMove(fenGame, m);
    }
    _activeGame = fenGame;
    _boardPosition = _getChessboardMap(_activeGame);

    Set<String> highlight = {};
    if (_solutionMoves.length > 1 && _solutionMoves[1].length >= 4) {
      highlight = {
        _solutionMoves[1].substring(0, 2),
        _solutionMoves[1].substring(2, 4),
      };
    }

    _buildHistoryReplay();
    // Point the replay bar at the first player solution move so they immediately see the answer!
    final int firstPlayerMoveHistoryIdx =
        (_setupReplaySteps.length + 1).clamp(0, _historyStates.length - 1);

    if (!mounted) return;
    setState(() {
      _selectedSquares.clear();
      _errorSquares.clear();
      _greenHighlights = highlight;
      _solutionWasRevealed = true;
      _gameState = 'feedback';
      _historyIndex = firstPlayerMoveHistoryIdx;
    });

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

  void _buildHistoryReplay() {
    _historyStates.clear();
    if (_currentPuzzle == null) return;

    _historyStates.add({
      'position': Map<String, String>.from(_stepbackStartPosition),
      'label': _visualizationDepth >= 100 ? 'Game Start (Move 1)' : 'Stepback Start',
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

  Widget _buildMovesCalculationCard() {
    final bool isDeepMode = _movesTable.length >= 6;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.psychology, color: Color(0xFF38BDF8), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _visualizationDepth >= 100
                        ? 'Full Game Moves (${_movesTable.length} ply):'
                        : 'Moves to Calculate in Head:',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              if (_currentPuzzle != null)
                Text(
                  'Puzzle ${_currentPuzzle!.rating}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_movesTable.isEmpty)
            const Text(
              'Calculate the moves in your head and solve on the board!',
              style: TextStyle(color: Colors.grey),
            )
          else if (isDeepMode) ...[
            // Mental Step Pacer for 6+ moves or Full Game!
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    onPressed: _mentalPacerIndex > 0
                        ? () => setState(() => _mentalPacerIndex--)
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Mental Focus: Step ${_mentalPacerIndex + 1} of ${_movesTable.length}',
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_movesTable[_mentalPacerIndex]['chessNotation']}  (${_movesTable[_mentalPacerIndex]['side']})',
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          _movesTable[_mentalPacerIndex]['label'] ?? '',
                          style: TextStyle(
                            color: _mentalPacerIndex == _movesTable.length - 1
                                ? const Color(0xFFF59E0B)
                                : Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                    onPressed: _mentalPacerIndex < _movesTable.length - 1
                        ? () => setState(() => _mentalPacerIndex++)
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Compact PGN Notation Chips (tap any move to jump pacer to it)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(_movesTable.length, (idx) {
                final row = _movesTable[idx];
                final isFocused = idx == _mentalPacerIndex;
                final isBlunder = idx == _movesTable.length - 1;
                return InkWell(
                  onTap: () => setState(() => _mentalPacerIndex = idx),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isFocused
                          ? const Color(0xFF38BDF8).withValues(alpha: 0.25)
                          : (isBlunder
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                              : const Color(0xFF0F172A)),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isFocused
                            ? const Color(0xFF38BDF8)
                            : (isBlunder
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
                                : const Color(0xFF334155)),
                      ),
                    ),
                    child: Text(
                      row['chessNotation'] ?? row['move'] ?? '',
                      style: TextStyle(
                        color: isFocused
                            ? Colors.white
                            : (isBlunder ? const Color(0xFFF59E0B) : Colors.white70),
                        fontWeight: isFocused || isBlunder ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ] else
            ..._movesTable.map(
              (row) => Padding(
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${row['label']}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recommendedTier = PuzzleService.getRecommendedTierForElo(_userElo);
    final recommendedLabel = PuzzleService.getTierDisplayName(recommendedTier);

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
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16.0, 10.0, 16.0, 28.0),
          child: Column(
            children: [
              // Settings Card: Visualization Depth & Difficulty Tier (Single Compact Card)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isRatedPuzzle ? const Color(0xFF334155) : const Color(0xFFF59E0B),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Depth Selector
                        Expanded(
                          child: Row(
                            children: [
                              const Text(
                                'Depth: ',
                                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                              Expanded(
                                child: DropdownButton<int>(
                                  value: _visualizationDepth,
                                  dropdownColor: const Color(0xFF1E293B),
                                  underline: const SizedBox(),
                                  isDense: true,
                                  isExpanded: true,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 1,
                                      child: Text('1 Move', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                    DropdownMenuItem(
                                      value: 2,
                                      child: Text('2 Moves', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                    DropdownMenuItem(
                                      value: 3,
                                      child: Text('3 Moves', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                    DropdownMenuItem(
                                      value: 4,
                                      child: Text('4 Moves', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                    DropdownMenuItem(
                                      value: 5,
                                      child: Text('5 Moves', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                    DropdownMenuItem(
                                      value: 7,
                                      child: Text('7 Moves 🔥', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                    DropdownMenuItem(
                                      value: 10,
                                      child: Text('10 Moves 🔥', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                    DropdownMenuItem(
                                      value: 999,
                                      child: Text('Full Game 🧠', style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null && val != _visualizationDepth) {
                                      setState(() {
                                        _visualizationDepth = val;
                                      });
                                      _loadNewPuzzle();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 20,
                          width: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          color: const Color(0xFF334155),
                        ),
                        // Difficulty Selector
                        Expanded(
                          child: Row(
                            children: [
                              const Text(
                                'Level: ',
                                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                              Expanded(
                                child: DropdownButton<String>(
                                  value: _selectedDifficulty,
                                  dropdownColor: const Color(0xFF1E293B),
                                  underline: const SizedBox(),
                                  isDense: true,
                                  isExpanded: true,
                                  items: [
                                    DropdownMenuItem(
                                      value: 'auto',
                                      child: Text(
                                        'Auto (${recommendedTier.toUpperCase()})',
                                        style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'easy',
                                      child: Text(
                                        'Easy (<1350)${recommendedTier == 'easy' ? ' ★' : ''}',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'medium',
                                      child: Text(
                                        'Medium${recommendedTier == 'medium' ? ' ★' : ''}',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'hard',
                                      child: Text(
                                        'Hard${recommendedTier == 'hard' ? ' ★' : ''}',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'master',
                                      child: Text(
                                        'Master (1750+)${recommendedTier == 'master' ? ' ★' : ''}',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null && val != _selectedDifficulty) {
                                      setState(() {
                                        _selectedDifficulty = val;
                                      });
                                      _loadNewPuzzle();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Compact Status Bar: Rated vs Unrated + Advice
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isRatedPuzzle
                            ? const Color(0xFF6366F1).withValues(alpha: 0.15)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isRatedPuzzle ? Icons.verified_outlined : Icons.info_outline,
                            size: 13,
                            color: _isRatedPuzzle ? const Color(0xFF818CF8) : const Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _isRatedPuzzle
                                  ? (_recordedMistakeForCurrentPuzzle && _lastEloDelta != null
                                      ? 'Mistake ($_lastEloDelta ELO) • Finish for XP!'
                                      : 'RATED (ELO $_userElo) • Advice: ${recommendedTier.toUpperCase()}')
                                  : 'UNRATED (Below $recommendedLabel) • No ELO change',
                              style: TextStyle(
                                color: _isRatedPuzzle ? const Color(0xFF818CF8) : const Color(0xFFF59E0B),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

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

              const SizedBox(height: 10),

              // Permanent Moves Table / Pacer
              _buildMovesCalculationCard(),

              const SizedBox(height: 10),

              if (_gameState == 'solving' || _gameState == 'opponent_moving') ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF6366F1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app, color: Color(0xFFF59E0B), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedSquares.isNotEmpty
                              ? 'From ${_selectedSquares.first.toUpperCase()} → Tap destination square (${_playerColor.toUpperCase()})!'
                              : (_stepIndex == 1
                                  ? 'Your turn (${_playerColor.toUpperCase()})! Tap start square in head, then destination.'
                                  : 'Great move! Now play the follow-up move for $_playerColor!'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFF59E0B)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.lightbulb_outline, color: Color(0xFFF59E0B), size: 15),
                        label: const Text(
                          'Solution',
                          style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        onPressed: _revealSolution,
                      ),
                    ],
                  ),
                ),
              ],

            if (_gameState == 'feedback') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (_solutionWasRevealed ? const Color(0xFFF59E0B) : const Color(0xFF10B981))
                      .withValues(alpha: 0.15),
                  border: Border.all(
                    color: _solutionWasRevealed ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _solutionWasRevealed ? Icons.lightbulb : Icons.stars,
                      color: _solutionWasRevealed ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _solutionWasRevealed
                                ? 'Solution Revealed!'
                                : 'Well done! Puzzle Solved!',
                            style: TextStyle(
                              color: _solutionWasRevealed
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF10B981),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _solutionWasRevealed
                                ? 'Use the < and > arrows below to replay the mental moves and winning solution! (${_isRatedPuzzle && _lastEloDelta != null ? '$_lastEloDelta ELO • ' : ''}Rating: $_userElo)'
                                : (!_isRatedPuzzle
                                    ? 'Unrated Mode (+10 Monthly XP • ELO unchanged: $_userElo)'
                                    : (_recordedMistakeForCurrentPuzzle
                                        ? 'Solved after mistake ($_lastEloDelta ELO • +8 Monthly XP • Rating: $_userElo)'
                                        : 'Flawless Solve! (+$_lastEloDelta ELO • New Rating: $_userElo)')),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
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
                            _historyStates[_historyIndex]['label'] as String,
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
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
            ],
            ],
          ),
        ),
      ),
    );
  }
}
