import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/audio_service.dart';
import '../widgets/chessboard_widget.dart';


import '../widgets/energy_dialog.dart';

import '../widgets/mode_info_dialog.dart';

class CoordinatesScreen extends StatefulWidget {
  const CoordinatesScreen({super.key});

  @override
  State<CoordinatesScreen> createState() => _CoordinatesScreenState();
}


class _CoordinatesScreenState extends State<CoordinatesScreen> {
  final StorageService _storageService = StorageService();
  final AudioService _audioService = AudioService();

  int _score = 0;

  int _highScore = 0;
  int _wrongClicks = 0;
  double _timeLeft = 60.0;
  Timer? _timer;

  String _targetSquare = 'e4';
  String _orientation = 'white';
  String _boardOrientationSetting = 'white'; // 'white', 'black', 'random'
  String _penaltyMode = 'none'; // 'none', 'penalty', 'sudden_death'
  bool _isPlaying = false;
  bool _isGameOver = false;

  Set<String> _greenHighlights = {};
  Set<String> _errorSquares = {};

  @override
  void initState() {
    super.initState();
    _loadHighScore();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _loadHighScore() async {
    final stats = await _storageService.loadUserStats();
    setState(() {
      _highScore = stats.coordinatesHighScore;
    });
  }

  void _startGame() async {
    final hasEnergy = await _storageService.consumeEnergy();
    if (!hasEnergy) {
      if (mounted) {
        EnergyDialog.show(context, onRefilled: () => _startGame());
      }
      return;
    }

    _timer?.cancel();
    setState(() {
      _score = 0;
      _wrongClicks = 0;
      _timeLeft = 60.0;
      _isPlaying = true;
      _isGameOver = false;
      _greenHighlights.clear();
      _errorSquares.clear();
      
      if (_boardOrientationSetting == 'white') {
        _orientation = 'white';
      } else if (_boardOrientationSetting == 'black') {
        _orientation = 'black';
      } else if (_boardOrientationSetting == 'random') {
        _orientation = Random().nextBool() ? 'white' : 'black';
      }
    });

    _generateNextTarget();
    _startTimer();
  }



  void _generateNextTarget() {
    final files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
    final ranks = ['1', '2', '3', '4', '5', '6', '7', '8'];
    final random = Random();

    String next;
    do {
      final f = files[random.nextInt(8)];
      final r = ranks[random.nextInt(8)];
      next = '$f$r';
    } while (next == _targetSquare);

    setState(() {
      _targetSquare = next;
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      setState(() {
        _timeLeft -= 0.1;
        if (_timeLeft <= 0) {
          _timeLeft = 0;
          _endGame();
        }
      });
    });
  }

  void _endGame() {
    _timer?.cancel();
    _audioService.playSuccess();
    setState(() {
      _isPlaying = false;
      _isGameOver = true;
    });

    _storageService.saveCoordsHighScore(_score);
    _storageService.recordActivity(_score > 0);
  }

  void _handleSquareTap(String square) {
    if (!_isPlaying) return;

    if (square == _targetSquare) {
      // Correct click!
      _audioService.playMove();
      setState(() {
        _score++;
        _greenHighlights = {square};
      });

      if (_boardOrientationSetting == 'random') {
        setState(() {
          _orientation = _orientation == 'white' ? 'black' : 'white';
        });
      }

      _generateNextTarget();

      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          setState(() {
            _greenHighlights.clear();
          });
        }
      });
    } else {
      // Incorrect click!
      _audioService.playError();
      setState(() {
        _wrongClicks++;
        _errorSquares = {square};
      });

      if (_penaltyMode == 'sudden_death') {
        _endGame();
      } else if (_penaltyMode == 'penalty') {
        setState(() {
          _timeLeft = max(0, _timeLeft - 5.0);
        });
      }

      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _errorSquares.clear();
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double accuracy = (_score + _wrongClicks) > 0 ? (_score / (_score + _wrongClicks)) * 100 : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text('Coordinates Trainer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Color(0xFF38BDF8)),
            tooltip: 'How to Play',
            onPressed: () => ModeInfoDialog.showCoordinatesInfo(context),
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_isPlaying) ...[
              // Prompt & Timer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  children: [
                    Text(
                      'Find: ${_targetSquare.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _timeLeft / 60.0,
                      backgroundColor: const Color(0xFF334155),
                      color: const Color(0xFF10B981),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Score: $_score', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Time: ${_timeLeft.ceil()}s', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Chessboard
            ChessboardWidget(
              position: const {},
              orientation: _orientation,
              greenHighlights: _greenHighlights,
              errorSquares: _errorSquares,
              onSquareTap: _handleSquareTap,
            ),

            const SizedBox(height: 20),

            if (!_isPlaying && !_isGameOver) ...[
              // Settings & Start Button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _boardOrientationSetting,
                      dropdownColor: const Color(0xFF1E293B),
                      decoration: const InputDecoration(
                        labelText: 'Board View',
                        labelStyle: TextStyle(color: Colors.grey),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'white', child: Text('⚪ White View (Standard)', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 'black', child: Text('🖤 Black View', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 'random', child: Text('🔀 Random Flips', style: TextStyle(color: Colors.white))),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _boardOrientationSetting = val;
                            if (val == 'white') _orientation = 'white';
                            if (val == 'black') _orientation = 'black';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _penaltyMode,

                      dropdownColor: const Color(0xFF1E293B),
                      decoration: const InputDecoration(
                        labelText: 'Penalty Mode',
                        labelStyle: TextStyle(color: Colors.grey),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('No Penalty (Default)', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 'penalty', child: Text('5s Penalty per error', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 'sudden_death', child: Text('Sudden Death (Immediate end)', style: TextStyle(color: Colors.white))),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _penaltyMode = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
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
                  icon: const Icon(Icons.play_arrow, color: Colors.white),
                  label: const Text('Start Training', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  onPressed: _startGame,
                ),
              ),
            ],

            if (_isGameOver) ...[
              // Results Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF6366F1)),
                ),
                child: Column(
                  children: [
                    const Text('Result', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('$_score', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: Color(0xFF818CF8))),
                    const Text('squares in 60s', style: TextStyle(color: Colors.white70)),
                    const Divider(height: 32, color: Color(0xFF334155)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text('Accuracy', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Text('${accuracy.round()}%', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 20)),
                          ],
                        ),
                        Column(
                          children: [
                            const Text('Errors', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Text('$_wrongClicks', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 20)),
                          ],
                        ),
                        Column(
                          children: [
                            const Text('Highscore', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Text('$_highScore', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 20)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
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
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text('Play Again (1⚡)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  onPressed: _startGame,
                ),
              ),


            ],
          ],
        ),
      ),
    );
  }
}
