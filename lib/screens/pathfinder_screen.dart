import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../services/audio_service.dart';
import '../services/ad_service.dart';
import '../widgets/chessboard_widget.dart';
import '../widgets/energy_dialog.dart';
import '../widgets/mode_info_dialog.dart';


class PathfinderScreen extends StatefulWidget {
  const PathfinderScreen({super.key});


  @override
  State<PathfinderScreen> createState() => _PathfinderScreenState();
}

class _PathfinderScreenState extends State<PathfinderScreen> {
  final StorageService _storageService = StorageService();
  final AudioService _audioService = AudioService();
  final AdService _adService = AdService();

  int _level = 1;
  int _movesCount = 0;
  int _minMoves = 0;

  String _knightSquare = 'a1';
  String _targetSquare = 'h8';
  String _initialKnightSquare = 'a1';

  final Map<String, String> _enemyPieces = {};
  final Map<String, String> _initialEnemyPieces = {};
  final Set<String> _controlledSquares = {};
  final Map<String, Set<String>> _squareAttackers = {};
  Set<String> _selectedSquares = {};
  Set<String> _errorSquares = {};

  bool _allowCaptures = true;
  bool _showDanger = false;
  bool _isCompleted = false;
  bool _isFailed = false;
  int _dangerHintCount = 0;
  Timer? _dangerFlashTimer;
  Set<String> _greenHighlights = {};

  @override
  void initState() {
    super.initState();
    _loadLevelAndGenerate();
  }

  @override
  void dispose() {
    _dangerFlashTimer?.cancel();
    super.dispose();
  }

  void _loadLevelAndGenerate() async {
    final stats = await _storageService.loadUserStats();
    _level = stats.pathfinderLevel;
    _generateLayout(consume: true);
  }

  void _skipOrGiveUpPuzzle() {
    _generateLayout(consume: true);
  }

  void _restartCurrentRoute() {
    _dangerFlashTimer?.cancel();
    setState(() {
      _knightSquare = _initialKnightSquare;
      _enemyPieces.clear();
      _enemyPieces.addAll(Map<String, String>.from(_initialEnemyPieces));
      _movesCount = 0;
      _dangerHintCount = 0;
      _showDanger = false;
      _selectedSquares = {_knightSquare};
      _errorSquares.clear();
      _greenHighlights.clear();
      _isCompleted = false;
      _isFailed = false;
      _recalculateControlledSquares();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route restarted! Try again.'), duration: Duration(milliseconds: 1000)),
    );
  }

  void _generateLayout({bool consume = true}) async {
    if (consume) {
      final hasEnergy = await _storageService.consumeEnergy();
      if (!hasEnergy) {
        if (mounted) {
          EnergyDialog.show(context, onRefilled: () => _generateLayout(consume: true));
        }
        return;
      }
    }

    final files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
    final ranks = ['1', '2', '3', '4', '5', '6', '7', '8'];
    final allSquares = <String>[];
    for (var f in files) {
      for (var r in ranks) {
        allSquares.add('$f$r');
      }
    }

    final random = Random();
    int attempts = 0;

    do {
      attempts++;
      final startIdx = random.nextInt(allSquares.length);
      int targetIdx = random.nextInt(allSquares.length);
      while (targetIdx == startIdx) {
        targetIdx = random.nextInt(allSquares.length);
      }

      _knightSquare = allSquares[startIdx];
      _targetSquare = allSquares[targetIdx];
      _movesCount = 0;
      _isCompleted = false;
      _isFailed = false;
      _errorSquares.clear();
      _greenHighlights.clear();

      // Enemy piece scaling: 0 at Level 1-2, +1 every 2 levels (max 8)
      final numEnemies = min(8, max(0, (_level - 1) ~/ 2));
      _enemyPieces.clear();
      final potential = allSquares.where((s) => s != _knightSquare && s != _targetSquare).toList();
      potential.shuffle();

      final enemyTypes = ['bB', 'bR', 'bQ'];
      for (int i = 0; i < numEnemies && i < potential.length; i++) {
        final sq = potential[i];
        final piece = enemyTypes[random.nextInt(enemyTypes.length)];
        _enemyPieces[sq] = piece;
      }

      _recalculateControlledSquares();
      _minMoves = _findShortestPathLength() ?? 0;

      // Ensure target square is NOT in danger zone and shortest path exists
    } while ((_controlledSquares.contains(_targetSquare) || _minMoves == 0) && attempts < 60);

    // Fallback safety if attempts exceeded
    if (_controlledSquares.contains(_targetSquare)) {
      _controlledSquares.remove(_targetSquare);
    }

    // Save initial state for Reset Route
    _initialKnightSquare = _knightSquare;
    _initialEnemyPieces.clear();
    _initialEnemyPieces.addAll(Map<String, String>.from(_enemyPieces));

    setState(() {
      _selectedSquares = {_knightSquare};
    });
  }

  List<String>? _findShortestPath() {
    final queue = [
      [_initialKnightSquare, <String>[_initialKnightSquare]]
    ];
    final visited = <String>{_initialKnightSquare};

    while (queue.isNotEmpty) {
      final item = queue.removeAt(0);
      final curr = item[0] as String;
      final path = item[1] as List<String>;

      if (curr == _targetSquare) return path;

      for (var next in _getKnightMoves(curr)) {
        if (visited.contains(next)) continue;
        if (_controlledSquares.contains(next)) continue;
        final isEnemy = _enemyPieces.containsKey(next);
        if (!_allowCaptures && isEnemy) continue;

        visited.add(next);
        queue.add([next, [...path, next]]);
      }
    }
    return null;
  }


  void _recalculateControlledSquares() {
    _controlledSquares.clear();
    _squareAttackers.clear();

    for (var entry in _enemyPieces.entries) {
      final attackerSq = entry.key;
      final piece = entry.value;
      final type = piece[1]; // 'B', 'R', 'Q'

      final f0 = attackerSq.codeUnitAt(0) - 97;
      final r0 = int.parse(attackerSq[1]) - 1;

      final directions = <List<int>>[];
      if (type == 'B' || type == 'Q') {
        directions.addAll([[-1, -1], [-1, 1], [1, -1], [1, 1]]);
      }
      if (type == 'R' || type == 'Q') {
        directions.addAll([[-1, 0], [1, 0], [0, -1], [0, 1]]);
      }

      for (var dir in directions) {
        int cf = f0 + dir[0];
        int cr = r0 + dir[1];

        while (cf >= 0 && cf < 8 && cr >= 0 && cr < 8) {
          final targetSq = '${String.fromCharCode(97 + cf)}${cr + 1}';
          
          _controlledSquares.add(targetSq);
          _squareAttackers.putIfAbsent(targetSq, () => {}).add(attackerSq);

          // Ray stops if blocked by another enemy piece or the knight
          if (_enemyPieces.containsKey(targetSq) || targetSq == _knightSquare) {
            break;
          }

          cf += dir[0];
          cr += dir[1];
        }
      }
    }
  }

  int? _findShortestPathLength() {
    final queue = [
      [_knightSquare, 0]
    ];
    final visited = <String>{_knightSquare};

    while (queue.isNotEmpty) {
      final item = queue.removeAt(0);
      final curr = item[0] as String;
      final dist = item[1] as int;

      if (curr == _targetSquare) return dist;

      for (var next in _getKnightMoves(curr)) {
        if (visited.contains(next)) continue;
        if (_controlledSquares.contains(next)) continue;
        final isEnemy = _enemyPieces.containsKey(next);
        if (!_allowCaptures && isEnemy) continue;

        visited.add(next);
        queue.add([next, dist + 1]);
      }
    }
    return null;
  }

  List<String> _getKnightMoves(String sq) {
    final moves = <String>[];
    final f = sq.codeUnitAt(0) - 97;
    final r = int.parse(sq[1]) - 1;

    final offsets = [
      [-2, -1], [-2, 1], [-1, -2], [-1, 2],
      [1, -2], [1, 2], [2, -1], [2, 1]
    ];

    for (var o in offsets) {
      final nf = f + o[0];
      final nr = r + o[1];
      if (nf >= 0 && nf < 8 && nr >= 0 && nr < 8) {
        moves.add('${String.fromCharCode(97 + nf)}${nr + 1}');
      }
    }
    return moves;
  }

  void _handleSquareTap(String to) {
    if (_isCompleted) return;

    final f1 = _knightSquare.codeUnitAt(0) - 97;
    final r1 = int.parse(_knightSquare[1]);
    final f2 = to.codeUnitAt(0) - 97;
    final r2 = int.parse(to[1]);

    final df = (f1 - f2).abs();
    final dr = (r1 - r2).abs();
    final isKnightMove = (df == 1 && dr == 2) || (df == 2 && dr == 1);

    if (!isKnightMove) {
      _audioService.playError();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A knight moves in an L-shape!'), duration: Duration(milliseconds: 800)),
      );
      return;
    }

    final isEnemy = _enemyPieces.containsKey(to);

    if (!_allowCaptures && isEnemy) {
      _audioService.playError();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Piece captures are disabled in settings!'), duration: Duration(milliseconds: 1000)),
      );
      return;
    }

    if (_controlledSquares.contains(to)) {
      _audioService.playError();
      final attackers = _squareAttackers[to] ?? {};
      final solution = _findShortestPath() ?? [];

      setState(() {
        _isFailed = true;
        _errorSquares = {to, ...attackers};
        _greenHighlights = solution.toSet();
      });
      return;
    }




    // Capture piece if landing on enemy
    bool captured = false;
    if (isEnemy && _allowCaptures) {
      _enemyPieces.remove(to);
      _recalculateControlledSquares();
      captured = true;
    }

    setState(() {
      _knightSquare = to;
      _selectedSquares = {to};
      _movesCount++;
    });

    if (captured) {
      _audioService.playCapture();
    } else {
      _audioService.playMove();
    }

    if (_showDanger) {
      _dangerFlashTimer?.cancel();
      _showDanger = false;
    }

    // Win condition
    if (_knightSquare == _targetSquare) {
      _audioService.playSuccess();
      setState(() {
        _isCompleted = true;
        _level++;
      });
      _storageService.savePathfinderLevel(_level);
      _storageService.recordActivity(true);
    }
  }

  void _flashDangerZone() {
    _dangerFlashTimer?.cancel();
    setState(() {
      _showDanger = true;
      _dangerHintCount++;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🛡️ Danger zones flashed! (-1 Star Penalty)'),
        duration: Duration(milliseconds: 1200),
      ),
    );

    _dangerFlashTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _showDanger = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> boardPos = {
      _knightSquare: 'wN',
      ..._enemyPieces,
    };

    int extraMoves = _movesCount - _minMoves;
    int totalPenalty = (extraMoves > 0 ? extraMoves : 0) + _dangerHintCount;

    int stars = 1;
    String starRatingTitle = '⭐ 1 Star Route';
    String starSubtitle = 'Used $_movesCount moves ($extraMoves extra moves, $_dangerHintCount danger hints used).';

    if (totalPenalty == 0) {
      stars = 3;
      starRatingTitle = '⭐⭐⭐ Perfect Route!';
      starSubtitle = 'Optimal solution found in $_movesCount moves with 0 danger hints!';
    } else if (totalPenalty == 1) {
      stars = 2;
      starRatingTitle = '⭐⭐ Great Route!';
      starSubtitle = 'Used $_movesCount moves (${extraMoves > 0 ? '$extraMoves extra move' : ''}${_dangerHintCount > 0 ? '1 danger hint (-1⭐)' : ''}).';
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text('Knight Pathfinder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Color(0xFF38BDF8)),
            tooltip: 'How to Play',
            onPressed: () => ModeInfoDialog.showPathfinderInfo(context),
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Level & Target Info Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Level $_level', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('Moves: $_movesCount (Min: $_minMoves)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  Text('Target: ${_targetSquare.toUpperCase()}', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Settings bar: Allow Captures toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: const Color(0xFF10B981),
                title: const Text(
                  'Allow Piece Captures',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Capture undefended enemy pieces along your path',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
                value: _allowCaptures,
                onChanged: (val) {
                  setState(() {
                    _allowCaptures = val;
                    _generateLayout(consume: false);
                  });
                },
              ),
            ),

            const SizedBox(height: 16),

            // Chessboard Widget
            ChessboardWidget(
              position: boardPos,
              selectedSquares: _selectedSquares,
              targetSquares: {_targetSquare},
              errorSquares: _errorSquares,
              greenHighlights: _greenHighlights,
              dangerSquares: _showDanger ? _controlledSquares : const {},
              onSquareTap: _handleSquareTap,
            ),

            const SizedBox(height: 20),

            // Actions & Controls
            if (!_isCompleted && !_isFailed) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _showDanger ? const Color(0xFFEF4444) : const Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: Icon(_showDanger ? Icons.warning : Icons.shield_outlined, color: _showDanger ? const Color(0xFFEF4444) : Colors.white),
                      label: Text(_showDanger ? 'Flash Active' : 'Flash Danger (-1⭐)', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: _flashDangerZone,
                    ),
                  ),

                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.replay, color: Colors.white, size: 18),
                      label: const Text('Reset Route', style: TextStyle(color: Colors.white, fontSize: 12)),
                      onPressed: _restartCurrentRoute,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.skip_next, color: Color(0xFFF59E0B), size: 18),
                      label: const Text('Skip (-1⚡)', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: _skipOrGiveUpPuzzle,
                    ),
                  ),
                ],
              ),
            ],

            if (_isFailed) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEF4444)),
                ),
                child: const Column(
                  children: [
                    Text(
                      '💥 Attacked Square! Level Failed',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'The optimal solution path is highlighted in green on the board above.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                      ),
                      icon: const Icon(Icons.shield, color: Color(0xFFF59E0B)),
                      label: const Text('Keep Level & Retry (Ad)', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        _adService.showRewardedAd(
                          onUserEarnedReward: () {
                            _restartCurrentRoute();
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text('Restart at Level 1 (-1⚡)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                      onPressed: () {
                        setState(() {
                          _level = 1;
                        });
                        _storageService.savePathfinderLevel(1);
                        _generateLayout(consume: true);
                      },
                    ),
                  ),
                ],
              ),
            ],


            if (_isCompleted) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: stars == 3
                        ? const Color(0xFF10B981)
                        : (stars == 2 ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B)),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      starRatingTitle,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: stars == 3
                            ? const Color(0xFF10B981)
                            : (stars == 2 ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      starSubtitle,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (stars == 1) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFFF59E0B)),
                        ),
                        icon: const Icon(Icons.replay, color: Color(0xFFF59E0B)),
                        label: const Text(
                          'Retry for ⭐⭐⭐ (0⚡)',
                          style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: _restartCurrentRoute,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.arrow_forward, color: Colors.white),
                        label: const Text('Next Level', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                        onPressed: () => _generateLayout(consume: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFF334155)),
                    ),
                    icon: const Icon(Icons.star, color: Color(0xFFF59E0B)),
                    label: const Text('Streak Saver (Ad)', style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      _adService.showRewardedAd(
                        onUserEarnedReward: () async {
                          final count = await _storageService.restoreStreak();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('🔥 Streak Restored ($count Days)! Awesome!')),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFF6366F1)),
                        ),
                        icon: const Icon(Icons.star, color: Color(0xFFF59E0B)),
                        label: const Text('Streak Saver (Ad)', style: TextStyle(color: Colors.white)),
                        onPressed: () {
                          _adService.showRewardedAd(
                            onUserEarnedReward: () async {
                              final count = await _storageService.restoreStreak();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('🔥 Streak Restored ($count Days)! Awesome!')),
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),

                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.arrow_forward, color: Colors.white),
                        label: const Text('Next Level', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        onPressed: () => _generateLayout(consume: true),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}




