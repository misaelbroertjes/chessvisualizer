import 'package:flutter/material.dart';
import '../models/user_stats.dart';
import '../services/storage_service.dart';
import '../services/puzzle_service.dart';
import '../services/ad_service.dart';
import 'stepback_screen.dart';
import 'pathfinder_screen.dart';
import 'coordinates_screen.dart';

import '../widgets/mode_info_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}


class _HomeScreenState extends State<HomeScreen> {
  final StorageService _storageService = StorageService();
  final PuzzleService _puzzleService = PuzzleService();
  final AdService _adService = AdService();

  UserStats _stats = UserStats();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  void _initializeApp() async {
    await _puzzleService.loadPuzzles();
    await _adService.initialize();
    _loadStats();
  }

  void _loadStats() async {
    final stats = await _storageService.loadUserStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.remove_red_eye_outlined, color: Color(0xFF6366F1)),
            SizedBox(width: 10),
            Text(
              'ChessVisualizer',
              style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        actions: [
          FutureBuilder<int>(
            future: _storageService.getRemainingEnergy(),
            builder: (context, snapshot) {
              final energy = snapshot.data ?? 10;
              return InkWell(
                onTap: () => ModeInfoDialog.showEnergyInfo(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt, color: Color(0xFFF59E0B), size: 18),
                      const SizedBox(width: 4),
                      Text(
                        '$energy/10',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 14),
                    ],
                  ),
                ),
              );
            },
          ),

        ],
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
          : RefreshIndicator(
              onRefresh: () async => _loadStats(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats & Daily Streak Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E293B), Color(0xFF334155)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),

                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Streak
                          InkWell(
                            onTap: () {
                              if (_stats.streakDays > 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('🔥 You are on a ${_stats.streakDays}-day streak! Keep training today!')),
                                );
                              } else {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: const Color(0xFF1E293B),
                                    title: const Text('🔥 Restore Streak', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    content: const Text('Did you miss a day? Watch a short ad to restore your daily streak!', style: TextStyle(color: Colors.white70)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                                      ),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
                                        icon: const Icon(Icons.play_circle_fill, color: Colors.white),
                                        label: const Text('Restore (Ad)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        onPressed: () {
                                          final messenger = ScaffoldMessenger.of(context);
                                          Navigator.pop(ctx);
                                          _adService.showRewardedAd(
                                            onUserEarnedReward: () async {
                                              final restored = await _storageService.restoreStreak();
                                              _loadStats();
                                              messenger.showSnackBar(
                                                SnackBar(content: Text('🔥 Streak Restored ($restored Days)! Awesome!')),
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              }
                            },
                            child: Column(
                              children: [
                                const Text('🔥 Streak', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('${_stats.streakDays} Days', style: TextStyle(color: _stats.streakDays > 0 ? const Color(0xFFF59E0B) : Colors.grey, fontWeight: FontWeight.w800, fontSize: 20)),
                              ],
                            ),
                          ),

                          Container(height: 30, width: 1, color: Colors.white24),
                          // Rating
                          Column(
                            children: [
                              const Text('⭐ Rating', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('${_stats.eloRating}', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w800, fontSize: 20)),
                            ],
                          ),
                          Container(height: 30, width: 1, color: Colors.white24),
                          // Solved
                          Column(
                            children: [
                              const Text('🎯 Solved', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('${_stats.totalPuzzlesSolved}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w800, fontSize: 20)),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    const Text('TRAINING MODES', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
                    const SizedBox(height: 12),

                    // Mode 1: Stepback
                    _buildModeCard(
                      title: 'Puzzle Stepback',
                      description: 'Calculate tactical puzzle sequences in your head before executing moves.',
                      icon: Icons.replay,
                      color: const Color(0xFF6366F1),
                      onInfoTap: () => ModeInfoDialog.showStepbackInfo(context),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const StepbackScreen())).then((_) => _loadStats());
                      },
                    ),

                    const SizedBox(height: 14),

                    // Mode 2: Knight Pathfinder
                    _buildModeCard(
                      title: 'Knight Pathfinder',
                      description: 'Guide knight safely to target square avoiding ray threats.',
                      icon: Icons.navigation,
                      color: const Color(0xFF10B981),
                      badgeText: 'Level ${_stats.pathfinderLevel}',
                      onInfoTap: () => ModeInfoDialog.showPathfinderInfo(context),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const PathfinderScreen())).then((_) => _loadStats());
                      },
                    ),

                    const SizedBox(height: 14),

                    // Mode 3: Coordinates Trainer
                    _buildModeCard(
                      title: 'Coordinates Trainer',
                      description: 'Find coordinates fast in 60s. Train blind board sight.',
                      icon: Icons.grid_4x4,
                      color: const Color(0xFFF59E0B),
                      badgeText: 'Best: ${_stats.coordinatesHighScore}',
                      onInfoTap: () => ModeInfoDialog.showCoordinatesInfo(context),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const CoordinatesScreen())).then((_) => _loadStats());
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildModeCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    String? badgeText,
    VoidCallback? onInfoTap,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      if (badgeText != null)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(badgeText, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      if (onInfoTap != null)
                        InkWell(
                          onTap: onInfoTap,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(Icons.info_outline, color: color.withValues(alpha: 0.8), size: 20),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

