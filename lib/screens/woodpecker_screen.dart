import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess_lib;
import '../models/puzzle.dart';
import '../services/puzzle_service.dart';
import '../services/storage_service.dart';
import '../services/audio_service.dart';
import '../widgets/chessboard_widget.dart';
import '../widgets/energy_dialog.dart';
import '../widgets/mode_info_dialog.dart';

class WoodpeckerScreen extends StatefulWidget {
  const WoodpeckerScreen({super.key});

  @override
  State<WoodpeckerScreen> createState() => _WoodpeckerScreenState();
}

class _WoodpeckerScreenState extends State<WoodpeckerScreen> with WidgetsBindingObserver {
  final PuzzleService _puzzleService = PuzzleService();
  final StorageService _storageService = StorageService();
  final AudioService _audioService = AudioService();

  // Persistent Set Configuration & Progress
  int _setNumber = 1;
  int _setSize = 10;
  int _targetSeconds = 0; // 0 == not set yet (chosen after Cycle #1 baseline!)
  String _difficultyTier = 'auto';
  int _userElo = 1200;

  List<String> _setPuzzleIds = [];
  List<Map<String, dynamic>> _cycleHistory = []; // [{cycle: 1, seconds: 112.4, mistakes: 2, passed: false}]
  List<String> _lastMissedPuzzleIds = [];

  // Screen mode: 'hub' (overview/settings), 'playing' (active cycle or mistake review), 'summary' (cycle finished)
  String _mode = 'hub';
  bool _isReviewingMistakes = false;
  bool _isPaused = false;

  // Active Cycle State
  int _currentCycleNumber = 1;
  List<Puzzle> _cyclePuzzles = [];
  int _currentPuzzleIndex = 0;
  int _cycleMistakes = 0;
  bool _mistakeOnCurrentPuzzle = false;
  double _elapsedSeconds = 0.0;
  Timer? _stopwatchTimer;
  final Set<String> _currentCycleMissedIds = {};

  // Board State for Current Puzzle
  Puzzle? _activePuzzle;
  late chess_lib.Chess _activeGame;
  Map<String, String> _boardPosition = {};
  String _playerColor = 'white';
  List<String> _solutionMoves = [];
  int _stepIndex = 1;
  String _boardStatus = 'solving'; // 'solving', 'opponent_moving'

  Set<String> _selectedSquares = {};
  Set<String> _greenHighlights = {};
  Set<String> _errorSquares = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedSetOrInit();
    _checkFirstTimeInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopwatchTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_mode == 'playing' && !_isReviewingMistakes) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden) {
        if (!_isPaused && mounted) {
          setState(() {
            _isPaused = true;
          });
        }
      }
    }
  }

  void _checkFirstTimeInfo() async {
    final seen = await _storageService.hasSeenModeInfo('woodpecker');
    if (!seen && mounted) {
      await _storageService.setSeenModeInfo('woodpecker');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ModeInfoDialog.showWoodpeckerInfo(context);
        }
      });
    }
  }

  Future<void> _loadSavedSetOrInit() async {
    await _puzzleService.loadPuzzles();
    final stats = await _storageService.loadUserStats();
    _userElo = stats.eloRating;

    final saved = await _storageService.loadWoodpeckerState();
    if (saved != null) {
      final ids = (saved['puzzleIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      if (ids.isNotEmpty) {
        setState(() {
          _setNumber = (saved['setNumber'] as num?)?.toInt() ?? 1;
          _setSize = (saved['setSize'] as num?)?.toInt() ?? 10;
          _targetSeconds = (saved['targetSeconds'] as num?)?.toInt() ?? 0;
          _difficultyTier = saved['difficultyTier'] as String? ?? 'auto';
          _setPuzzleIds = ids;
          _cycleHistory = (saved['cycleHistory'] as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [];
          _lastMissedPuzzleIds = (saved['lastMissedPuzzleIds'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
        });
        return;
      }
    }

    _generateNewSet(resetSetNumber: false);
  }

  Future<void> _saveCurrentSetState() async {
    await _storageService.saveWoodpeckerState({
      'setNumber': _setNumber,
      'setSize': _setSize,
      'targetSeconds': _targetSeconds,
      'difficultyTier': _difficultyTier,
      'puzzleIds': _setPuzzleIds,
      'cycleHistory': _cycleHistory,
      'lastMissedPuzzleIds': _lastMissedPuzzleIds,
    });
  }

  void _generateNewSet({bool resetSetNumber = false, bool advanceSetNumber = false}) {
    if (resetSetNumber) {
      _setNumber = 1;
    } else if (advanceSetNumber) {
      _setNumber++;
    }

    final puzzles = _puzzleService.generateWoodpeckerSet(
      count: _setSize,
      difficultyTier: _difficultyTier,
      userElo: _userElo,
    );

    setState(() {
      _setPuzzleIds = puzzles.map((p) => p.id).toList();
      _cycleHistory = [];
      _lastMissedPuzzleIds = [];
      _targetSeconds = 0; // Chosen after Cycle #1 baseline!
      _mode = 'hub';
      _isReviewingMistakes = false;
      _isPaused = false;
    });
    _saveCurrentSetState();
  }

  void _startCycle() {
    final puzzles = <Puzzle>[];
    for (final id in _setPuzzleIds) {
      final p = _puzzleService.getPuzzleById(id);
      if (p != null) puzzles.add(p);
    }

    if (puzzles.isEmpty) {
      _generateNewSet();
      return;
    }

    // Shuffle puzzles each cycle so player recognizes board patterns rather than order
    puzzles.shuffle(Random());

    _stopwatchTimer?.cancel();
    setState(() {
      _cyclePuzzles = puzzles;
      _currentCycleNumber = _cycleHistory.length + 1;
      _currentPuzzleIndex = 0;
      _cycleMistakes = 0;
      _currentCycleMissedIds.clear();
      _elapsedSeconds = 0.0;
      _isReviewingMistakes = false;
      _isPaused = false;
      _mode = 'playing';
    });

    _loadPuzzleAtIndex(0);

    _stopwatchTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _mode != 'playing' || _isPaused || _isReviewingMistakes) return;
      setState(() {
        _elapsedSeconds += 0.1;
      });
    });
  }

  void _startMistakeReview() {
    final puzzles = <Puzzle>[];
    for (final id in _lastMissedPuzzleIds) {
      final p = _puzzleService.getPuzzleById(id);
      if (p != null) puzzles.add(p);
    }
    if (puzzles.isEmpty) return;

    _stopwatchTimer?.cancel();
    setState(() {
      _cyclePuzzles = puzzles;
      _currentPuzzleIndex = 0;
      _isReviewingMistakes = true;
      _isPaused = false;
      _mode = 'playing';
    });

    _loadPuzzleAtIndex(0);
  }

  Future<void> _confirmAbortCycle() async {
    final wasAlreadyPaused = _isPaused;
    if (!_isReviewingMistakes) {
      setState(() => _isPaused = true);
    }

    final shouldAbort = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _isReviewingMistakes ? 'Exit Mistake Review?' : 'Abort Current Cycle?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        content: Text(
          _isReviewingMistakes
              ? 'Return to your cycle summary?'
              : 'Your progress in Cycle #$_currentCycleNumber will not be saved. Return to the Set Overview?',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Playing', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (shouldAbort == true) {
      _stopwatchTimer?.cancel();
      setState(() {
        _isPaused = false;
        _mode = _isReviewingMistakes ? 'summary' : 'hub';
        _isReviewingMistakes = false;
      });
    } else if (!wasAlreadyPaused) {
      setState(() => _isPaused = false);
    }
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

  Map<String, String> _getChessboardMap(chess_lib.Chess game) {
    final Map<String, String> pos = {};
    const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
    const ranks = ['1', '2', '3', '4', '5', '6', '7', '8'];

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

  void _loadPuzzleAtIndex(int index) {
    final puzzle = _cyclePuzzles[index];
    _activePuzzle = puzzle;
    _solutionMoves = List.from(puzzle.solution);
    _stepIndex = 1;
    _mistakeOnCurrentPuzzle = false;

    final fenParts = puzzle.fen.split(' ');
    final blunderColor = fenParts.length > 1 ? fenParts[1] : 'w';
    _playerColor = blunderColor == 'w' ? 'black' : 'white';

    final game = chess_lib.Chess.fromFEN(puzzle.fen);
    Set<String> initialHighlights = {};
    if (_solutionMoves.isNotEmpty && _solutionMoves[0].length >= 4) {
      final oppFrom = _solutionMoves[0].substring(0, 2);
      final oppTo = _solutionMoves[0].substring(2, 4);
      _makeMove(game, _solutionMoves[0]);
      initialHighlights = {oppFrom, oppTo};
    }

    _activeGame = game;
    setState(() {
      _boardPosition = _getChessboardMap(_activeGame);
      _selectedSquares = {};
      _greenHighlights = initialHighlights;
      _errorSquares = {};
      _boardStatus = 'solving';
    });
  }

  Future<void> _handleSquareTap(String square) async {
    if (_mode != 'playing' || _isPaused || _boardStatus != 'solving' || _activePuzzle == null) return;
    if (_stepIndex >= _solutionMoves.length) return;

    final expectedMove = _solutionMoves[_stepIndex];
    final expectedFrom = expectedMove.length >= 4 ? expectedMove.substring(0, 2) : '';
    final expectedTo = expectedMove.length >= 4 ? expectedMove.substring(2, 4) : '';
    final playerPrefix = _playerColor == 'white' ? 'w' : 'b';

    if (_selectedSquares.isEmpty) {
      if (_boardPosition[square]?.startsWith(playerPrefix) == true) {
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

    if (_boardPosition[to]?.startsWith(playerPrefix) == true && to != expectedTo) {
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

    if (from == expectedFrom && to == expectedTo) {
      _executeCorrectStep(expectedMove, expectedFrom, expectedTo);
    } else {
      _audioService.playError();
      setState(() {
        if (!_mistakeOnCurrentPuzzle) {
          _mistakeOnCurrentPuzzle = true;
          if (!_isReviewingMistakes) {
            _cycleMistakes++;
            _currentCycleMissedIds.add(_activePuzzle!.id);
          }
        }
        _errorSquares = {from, to};
      });

      _storageService.consumeEnergy().then((hasEnergy) {
        if (!hasEnergy && mounted) {
          EnergyDialog.show(context, onRefilled: () {});
        }
      });

      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _errorSquares.clear();
          });
        }
      });
    }
  }

  void _executeCorrectStep(String expectedMove, String expectedFrom, String expectedTo) {
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

    if (_stepIndex + 2 < _solutionMoves.length) {
      setState(() {
        _greenHighlights = {expectedFrom, expectedTo};
        _boardStatus = 'opponent_moving';
      });

      final opponentMove = _solutionMoves[_stepIndex + 1];
      final oppFrom = opponentMove.length >= 4 ? opponentMove.substring(0, 2) : '';
      final oppTo = opponentMove.length >= 4 ? opponentMove.substring(2, 4) : '';

      Future.delayed(const Duration(milliseconds: 280), () {
        if (!mounted || _mode != 'playing') return;
        final oppCapture = _activeGame.get(oppTo) != null;
        _makeMove(_activeGame, opponentMove);
        _boardPosition = _getChessboardMap(_activeGame);

        if (_activeGame.in_check) {
          _audioService.playCheck();
        } else if (oppCapture) {
          _audioService.playCapture();
        } else {
          _audioService.playMove();
        }

        setState(() {
          _stepIndex += 2;
          _greenHighlights = {oppFrom, oppTo};
          _boardStatus = 'solving';
        });
      });
    } else {
      // Puzzle finished! Move to next puzzle in cycle or finish cycle
      setState(() {
        _greenHighlights = {expectedFrom, expectedTo};
        _boardStatus = 'opponent_moving';
      });

      Future.delayed(const Duration(milliseconds: 260), () {
        if (!mounted || _mode != 'playing') return;
        if (_currentPuzzleIndex + 1 < _cyclePuzzles.length) {
          setState(() {
            _currentPuzzleIndex++;
          });
          _loadPuzzleAtIndex(_currentPuzzleIndex);
        } else {
          if (_isReviewingMistakes) {
            _audioService.playSuccess();
            setState(() {
              _isReviewingMistakes = false;
              _lastMissedPuzzleIds.clear();
              _mode = 'summary';
            });
            _saveCurrentSetState();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ All missed puzzles reviewed! Ready for your next cycle!'),
              ),
            );
          } else {
            _finishCycle();
          }
        }
      });
    }
  }

  void _showHintMove() {
    if (_mode != 'playing' || _isPaused || _boardStatus != 'solving' || _activePuzzle == null) return;
    if (_stepIndex >= _solutionMoves.length) return;

    final expectedMove = _solutionMoves[_stepIndex];
    final expectedFrom = expectedMove.length >= 4 ? expectedMove.substring(0, 2) : '';
    final expectedTo = expectedMove.length >= 4 ? expectedMove.substring(2, 4) : '';

    setState(() {
      if (!_mistakeOnCurrentPuzzle) {
        _mistakeOnCurrentPuzzle = true;
        if (!_isReviewingMistakes) {
          _cycleMistakes++;
          _currentCycleMissedIds.add(_activePuzzle!.id);
        }
      }
      _selectedSquares = {expectedFrom};
    });
    _executeCorrectStep(expectedMove, expectedFrom, expectedTo);
  }

  Future<void> _finishCycle() async {
    _stopwatchTimer?.cancel();
    _audioService.playSuccess();

    final bool wasBaselineWithoutTarget = _targetSeconds <= 0;
    if (wasBaselineWithoutTarget) {
      // Suggest a realistic target time based on Cycle #1 (e.g. 60% of baseline time, rounded to 5s, min 15s)
      final suggested = ((_elapsedSeconds * 0.65) / 5).round() * 5;
      _targetSeconds = suggested.clamp(15, 600);
    }

    final bool passed = !wasBaselineWithoutTarget &&
        _cycleMistakes == 0 &&
        _elapsedSeconds <= _targetSeconds;

    final entry = <String, dynamic>{
      'cycle': _currentCycleNumber,
      'seconds': double.parse(_elapsedSeconds.toStringAsFixed(1)),
      'mistakes': _cycleMistakes,
      'passed': passed,
    };

    setState(() {
      _cycleHistory.add(entry);
      _lastMissedPuzzleIds = _currentCycleMissedIds.toList();
      _mode = 'summary';
    });

    await _saveCurrentSetState();

    final int baseXp = _cyclePuzzles.length * 2;
    final int bonusXp = passed ? 30 : (_cycleMistakes == 0 ? 10 : 0);
    await _storageService.recordModeTraining(
      xpEarned: baseXp + bonusXp,
      puzzlesSolvedDelta: _cyclePuzzles.length,
      updateDailyStreak: true,
    );

    if (passed) {
      await _storageService.incrementWoodpeckerSetsCompleted();
    }
  }

  String _formatDuration(double totalSeconds) {
    final int mins = totalSeconds ~/ 60;
    final int secs = (totalSeconds % 60).floor();
    final int tenths = ((totalSeconds - totalSeconds.floor()) * 10).floor();
    if (mins > 0) {
      return '${mins}m ${secs.toString().padLeft(2, '0')}.${tenths}s';
    }
    return '$secs.${tenths}s';
  }

  String _formatTargetTime(int seconds) {
    if (seconds <= 0) return 'After Cycle #1';
    final int mins = seconds ~/ 60;
    final int secs = seconds % 60;
    if (mins > 0 && secs > 0) return '${mins}m ${secs}s';
    if (mins > 0) return '${mins}m';
    return '${secs}s';
  }

  void _showConfigureSetDialog() {
    int tempSize = _setSize;
    int tempTarget = _targetSeconds > 0 ? _targetSeconds : (_setSize * 6).clamp(15, 600);
    String tempTier = _difficultyTier;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final bool configChanged = tempSize != _setSize || tempTier != _difficultyTier;
            final secPerPuzzle = (tempTarget / tempSize).toStringAsFixed(1);
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                '🐦 Set & Target Settings',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_cycleHistory.isNotEmpty) ...[
                      Text(
                        'Target Time Goal: ${_formatTargetTime(tempTarget)} ($secPerPuzzle s/puzzle)',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Slider(
                        value: tempTarget.toDouble().clamp(10.0, 600.0),
                        min: 10,
                        max: 600,
                        divisions: 118,
                        activeColor: const Color(0xFF38BDF8),
                        onChanged: (val) {
                          setDialogState(() {
                            tempTarget = (val / 5).round() * 5;
                          });
                        },
                      ),
                      const Divider(color: Color(0xFF334155), height: 20),
                    ],
                    const Text(
                      'Puzzles in Set:',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [5, 10, 15, 20, 30, 50].map((size) {
                        final selected = tempSize == size;
                        return ChoiceChip(
                          label: Text('$size'),
                          selected: selected,
                          selectedColor: const Color(0xFFEC4899),
                          backgroundColor: const Color(0xFF0F172A),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (_) {
                            setDialogState(() {
                              final double ratio = size / tempSize;
                              tempSize = size;
                              tempTarget = ((tempTarget * ratio) / 5).round() * 5;
                              tempTarget = tempTarget.clamp(10, 600);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Puzzle Difficulty:',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: tempTier,
                      dropdownColor: const Color(0xFF0F172A),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Color(0xFF0F172A),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'auto', child: Text('Auto (Match my ELO)', style: TextStyle(color: Color(0xFF10B981)))),
                        DropdownMenuItem(value: 'easy', child: Text('Easy (<1350)', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 'medium', child: Text('Medium (1350-1550)', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 'hard', child: Text('Hard (1550-1750)', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 'master', child: Text('Master (1750+)', style: TextStyle(color: Colors.white))),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            tempTier = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      configChanged
                          ? 'Changing Set Size or Difficulty generates a new set of puzzles.'
                          : 'You can save your updated Target Time for the current set, or generate a fresh set of puzzles.',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                if (!configChanged && _cycleHistory.isNotEmpty)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _targetSeconds = tempTarget;
                      });
                      _saveCurrentSetState();
                    },
                    child: const Text('Save Target Time', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
                  ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEC4899)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _setSize = tempSize;
                      _difficultyTier = tempTier;
                    });
                    _generateNewSet(resetSetNumber: false);
                  },
                  child: const Text('New Set', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTargetTimePickerAfterBaseline(double baselineSeconds) {
    final int halfSec = ((baselineSeconds * 0.50) / 5).round().clamp(2, 120) * 5;
    final int fastSec = ((baselineSeconds * 0.65) / 5).round().clamp(2, 120) * 5;
    final int steadySec = ((baselineSeconds * 0.80) / 5).round().clamp(2, 120) * 5;
    final secPerPuzzle = (_targetSeconds / _setSize).toStringAsFixed(1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.flag_circle, color: Color(0xFF38BDF8), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Choose Your Target Time Goal',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              Text(
                '${_formatTargetTime(_targetSeconds)} ($secPerPuzzle s/puz)',
                style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Your Cycle #1 baseline was ${_formatDuration(baselineSeconds)}. Pick the target time you want to beat with 0 mistakes:',
            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildPresetTargetChip('🔥 Half (${_formatTargetTime(halfSec)})', halfSec),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildPresetTargetChip('⚡ -35% (${_formatTargetTime(fastSec)})', fastSec),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildPresetTargetChip('🎯 -20% (${_formatTargetTime(steadySec)})', steadySec),
              ),
            ],
          ),
          Slider(
            value: _targetSeconds.toDouble().clamp(10.0, 600.0),
            min: 10,
            max: 600,
            divisions: 118,
            activeColor: const Color(0xFF38BDF8),
            onChanged: (val) {
              setState(() {
                _targetSeconds = (val / 5).round() * 5;
              });
              _saveCurrentSetState();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPresetTargetChip(String label, int seconds) {
    final isSelected = _targetSeconds == seconds;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        setState(() {
          _targetSeconds = seconds;
        });
        _saveCurrentSetState();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF38BDF8).withValues(alpha: 0.22) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF38BDF8) : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildCycleHistoryCard() {
    if (_cycleHistory.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: const Column(
          children: [
            Icon(Icons.timer_outlined, color: Color(0xFF38BDF8), size: 28),
            SizedBox(height: 8),
            Text(
              'Step 1: Complete Cycle #1 (Baseline)',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            SizedBox(height: 4),
            Text(
              'First solve all puzzles in the set once to establish your baseline time. Right after Cycle #1, you choose your Target Time goal for the next cycles!',
              style: TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final firstTime = (_cycleHistory.first['seconds'] as num).toDouble();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.timeline, color: Color(0xFFEC4899), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Set Cycle Progression',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              if (_targetSeconds > 0)
                Text(
                  'Goal: <= ${_formatTargetTime(_targetSeconds)} & 0 ❌',
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ..._cycleHistory.map((item) {
            final int cNum = (item['cycle'] as num).toInt();
            final double secs = (item['seconds'] as num).toDouble();
            final int mistakes = (item['mistakes'] as num).toInt();
            final bool passed = item['passed'] == true;
            final double speedupPct =
                cNum > 1 && firstTime > 0 ? ((firstTime - secs) / firstTime * 100) : 0.0;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: passed
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: passed ? const Color(0xFF10B981) : const Color(0xFF334155),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        cNum == 1 ? 'Cycle #1 (Baseline)' : 'Cycle #$cNum',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (speedupPct > 1) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '-${speedupPct.round()}% time',
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        _formatDuration(secs),
                        style: TextStyle(
                          color: (_targetSeconds > 0 && secs <= _targetSeconds)
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        mistakes == 0 ? '0 ❌ ✅' : '$mistakes ❌',
                        style: TextStyle(
                          color: mistakes == 0
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (passed) ...[
                        const SizedBox(width: 6),
                        const Text('🏆'),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasMasteredCurrentSet =
        _cycleHistory.any((c) => c['passed'] == true);

    return PopScope(
      canPop: _mode != 'playing',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _mode == 'playing') {
          _confirmAbortCycle();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_mode == 'playing') {
                _confirmAbortCycle();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: const Text(
            'Woodpecker Rush',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          actions: [
            if (_mode == 'playing' && !_isReviewingMistakes)
              IconButton(
                icon: Icon(
                  _isPaused ? Icons.play_arrow_rounded : Icons.pause_circle_outline,
                  color: const Color(0xFFF59E0B),
                ),
                tooltip: _isPaused ? 'Resume' : 'Pause (hides board)',
                onPressed: () {
                  setState(() {
                    _isPaused = !_isPaused;
                  });
                },
              ),
            if (_mode != 'playing')
              IconButton(
                icon: const Icon(Icons.tune, color: Color(0xFFEC4899)),
                tooltip: 'Set Settings',
                onPressed: _showConfigureSetDialog,
              ),
            IconButton(
              icon: const Icon(Icons.palette_outlined, color: Color(0xFF38BDF8)),
              tooltip: 'Board Theme',
              onPressed: () => ChessboardWidget.showThemePicker(context),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline, color: Color(0xFF38BDF8)),
              tooltip: 'How to Play',
              onPressed: () => ModeInfoDialog.showWoodpeckerInfo(context),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 28.0),
            child: Column(
              children: [
                if (_mode == 'hub') ...[
                  // Set Header Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E293B), Color(0xFF334155)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEC4899).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.repeat_rounded, color: Color(0xFFEC4899), size: 28),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Woodpecker Set #$_setNumber',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18,
                                      ),
                                    ),
                                    Text(
                                      '${PuzzleService.getTierDisplayName(_difficultyTier)} • $_setSize Puzzles',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFEC4899)),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.settings, size: 15, color: Color(0xFFEC4899)),
                              label: const Text('Adjust', style: TextStyle(color: Color(0xFFEC4899), fontSize: 12)),
                              onPressed: _showConfigureSetDialog,
                            ),
                          ],
                        ),
                        const Divider(height: 24, color: Colors.white24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text('Set Size', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                const SizedBox(height: 2),
                                Text('$_setSize Puzzles', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                              ],
                            ),
                            Column(
                              children: [
                                const Text('Target Time', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                const SizedBox(height: 2),
                                Text(
                                  _formatTargetTime(_targetSeconds),
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                const Text('Next Cycle', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                const SizedBox(height: 2),
                                Text('Cycle #${_cycleHistory.length + 1}', style: const TextStyle(color: Color(0xFFEC4899), fontWeight: FontWeight.bold, fontSize: 15)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildCycleHistoryCard(),
                  const SizedBox(height: 16),
                  if (_lastMissedPuzzleIds.isNotEmpty) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.psychology_alt, color: Color(0xFFF59E0B)),
                        label: Text(
                          '🎯 Practice Missed Puzzles (${_lastMissedPuzzleIds.length})',
                          style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: _startMistakeReview,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEC4899),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                      label: Text(
                        _cycleHistory.isEmpty
                            ? 'Start Cycle #1 Baseline ($_setSize Puzzles)'
                            : 'Start Cycle #${_cycleHistory.length + 1} ($_setSize Puzzles)',
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      onPressed: _startCycle,
                    ),
                  ),
                  if (hasMasteredCurrentSet) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF10B981)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.skip_next, color: Color(0xFF10B981)),
                        label: Text(
                          'Advance to Set #${_setNumber + 1}',
                          style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _generateNewSet(advanceSetNumber: true),
                      ),
                    ),
                  ],
                ],

                if (_mode == 'playing') ...[
                  // Compact 2-Row Live Cycle Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _isReviewingMistakes
                                  ? '🎯 Mistake Review (${_currentPuzzleIndex + 1}/${_cyclePuzzles.length})'
                                  : 'Set #$_setNumber • Cycle #$_currentCycleNumber (${_currentPuzzleIndex + 1}/${_cyclePuzzles.length})',
                              style: const TextStyle(color: Color(0xFFEC4899), fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            if (!_isReviewingMistakes)
                              Row(
                                children: [
                                  const Icon(Icons.timer_outlined, size: 15, color: Color(0xFF38BDF8)),
                                  const SizedBox(width: 4),
                                  Text(
                                    _targetSeconds > 0
                                        ? '${_formatDuration(_elapsedSeconds)} / ${_formatTargetTime(_targetSeconds)}'
                                        : '${_formatDuration(_elapsedSeconds)} (Baseline)',
                                    style: TextStyle(
                                      color: (_targetSeconds <= 0 || _elapsedSeconds <= _targetSeconds)
                                          ? const Color(0xFF38BDF8)
                                          : const Color(0xFFF59E0B),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _cycleMistakes == 0 ? '0 ❌' : '$_cycleMistakes ❌',
                                    style: TextStyle(
                                      color: _cycleMistakes == 0
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFEF4444),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: (_currentPuzzleIndex + 1) / _cyclePuzzles.length,
                          backgroundColor: const Color(0xFF334155),
                          color: const Color(0xFFEC4899),
                          minHeight: 5,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Chessboard or Anti-Cheat Pause Cover
                  if (_isPaused)
                    AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6), width: 2),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.visibility_off_rounded, size: 54, color: Color(0xFFF59E0B)),
                            const SizedBox(height: 14),
                            const Text(
                              'Cycle Paused',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'The board is hidden while paused so the timer stays fair.',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                              label: const Text(
                                'Resume Cycle',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              onPressed: () => setState(() => _isPaused = false),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _confirmAbortCycle,
                              child: const Text(
                                'Abort Cycle & Return to Overview',
                                style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ChessboardWidget(
                      position: _boardPosition,
                      orientation: _playerColor,
                      selectedSquares: _selectedSquares,
                      greenHighlights: _greenHighlights,
                      errorSquares: _errorSquares,
                      onSquareTap: _handleSquareTap,
                    ),

                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _mistakeOnCurrentPuzzle ? const Color(0xFFF59E0B) : const Color(0xFF334155),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Play best move for ${_playerColor.toUpperCase()}!',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: _mistakeOnCurrentPuzzle
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.16)
                                : Colors.transparent,
                          ),
                          onPressed: _showHintMove,
                          icon: const Icon(Icons.lightbulb_outline, color: Color(0xFFF59E0B), size: 17),
                          label: Text(
                            _mistakeOnCurrentPuzzle || _isReviewingMistakes
                                ? 'Show Move (Free)'
                                : 'Show Move (+1❌)',
                            style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_mode == 'summary') ...[
                  Builder(
                    builder: (context) {
                      final bool isFirstBaseline = _cycleHistory.length == 1;
                      final bool passed = !isFirstBaseline &&
                          _cycleMistakes == 0 &&
                          _targetSeconds > 0 &&
                          _elapsedSeconds <= _targetSeconds;
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: passed ? const Color(0xFF10B981) : const Color(0xFFEC4899),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              passed
                                  ? '🏆 SET #$_setNumber MASTERED!'
                                  : (isFirstBaseline
                                      ? '⏱️ Cycle #1 Baseline Complete!'
                                      : 'Cycle #$_currentCycleNumber Complete!'),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: passed ? const Color(0xFF10B981) : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              passed
                                  ? 'You solved all $_setSize puzzles in ${_formatDuration(_elapsedSeconds)} (Goal: ${_formatTargetTime(_targetSeconds)}) with 0 mistakes! Ready for the next set!'
                                  : (isFirstBaseline
                                      ? 'You solved the set in ${_formatDuration(_elapsedSeconds)} with $_cycleMistakes mistake(s). Now pick your Target Time below and repeat the set faster!'
                                      : (_cycleMistakes > 0
                                          ? 'Finished in ${_formatDuration(_elapsedSeconds)} with $_cycleMistakes mistake(s). Practice your missed puzzles below or start the next cycle!'
                                          : 'Flawless 0 mistakes! Now shave off ${(_elapsedSeconds - _targetSeconds).toStringAsFixed(1)}s to beat your ${_formatTargetTime(_targetSeconds)} goal!')),
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  if (_cycleHistory.isNotEmpty)
                    _buildTargetTimePickerAfterBaseline(
                      (_cycleHistory.first['seconds'] as num).toDouble(),
                    ),
                  if (_lastMissedPuzzleIds.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFF59E0B), width: 1.6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.psychology_alt, color: Color(0xFFF59E0B)),
                        label: Text(
                          '🎯 Practice Missed Puzzles First (${_lastMissedPuzzleIds.length})',
                          style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: _startMistakeReview,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _buildCycleHistoryCard(),
                  const SizedBox(height: 14),
                  if (_cycleHistory.length > 1 && _cycleMistakes == 0 && _elapsedSeconds <= _targetSeconds) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.arrow_forward, color: Colors.white),
                        label: Text(
                          'Start Next Set (Set #${_setNumber + 1})',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _generateNewSet(advanceSetNumber: true),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEC4899),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.replay, color: Colors.white),
                      label: Text(
                        'Start Cycle #${_cycleHistory.length + 1} (Same Set, Shuffled)',
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _startCycle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
