import 'package:flutter/material.dart';

class ModeInfoDialog extends StatelessWidget {
  final String title;
  final String icon;
  final List<String> objectives;
  final List<String> rules;
  final List<String> tips;

  const ModeInfoDialog({
    super.key,
    required this.title,
    required this.icon,
    required this.objectives,
    required this.rules,
    required this.tips,
  });

  static Future<void> showCoordinatesInfo(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const ModeInfoDialog(
        title: 'Coordinates Trainer',
        icon: '🎯',
        objectives: [
          'Master chess notation and instant square identification.',
          'Find as many board coordinates as possible in 60 seconds.',
        ],
        rules: [
          '⚡ Costs 1 Energy per 60-second speed training session.',
          'Tap the square on the board that matches the target coordinate prompt.',
          'Penalty Mode: Removes 1 second for every incorrect tap.',
          'Sudden Death: Ends session immediately on a single mistake.',
          'Board View: Practice with White, Black, or Random orientation.',
        ],
        tips: [
          'Anchor your vision: Remember corner squares (a1, a8, h1, h8) and central squares (d4, d5, e4, e5).',
          'Practice with Black orientation to build complete board symmetry.',
        ],
      ),
    );
  }

  static Future<void> showPathfinderInfo(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const ModeInfoDialog(
        title: 'Knight Pathfinder',
        icon: '🐴',
        objectives: [
          'Train knight navigation and threat avoidance across the board.',
          'Guide your knight safely to the target square in minimum moves.',
        ],
        rules: [
          '⚡ Energy Rule: Level generation, route navigation, hints, and restarts are 100% FREE.',
          '💥 Mistake (-1⚡): Landing on a square controlled by an enemy threat ray costs 1 Energy.',
          '❌ Inefficient Route (-1⚡): Taking 3+ extra moves or hints fails the route and costs 1 Energy.',
          '⭐⭐⭐ Star Rating: 3 stars for optimal route, 2 stars for +1 extra move/hint (-1⭐), 1 star for +2 extra moves/hints (-2⭐).',
          'Level Progression: Enemy pieces increase by +1 piece every 2 levels up to max 8.',
        ],
        tips: [
          'Use the 🛡️ "Show Danger" button if you need to visualize threat rays.',
          'Use "Reset Route" to retry the same layout for free to find the optimal path!',
        ],
      ),
    );
  }

  static Future<void> showStepbackInfo(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const ModeInfoDialog(
        title: 'Puzzle Stepback',
        icon: '🧩',
        objectives: [
          'Calculate tactical puzzle sequences in your head before executing moves.',
          'Enhance calculation depth and mental vision.',
        ],
        rules: [
          '⚡ Energy Rule: Calculating moves in your head, switching depth, loading puzzles, and solving correctly costs 0 Energy (FREE!).',
          '❌ Wrong Move (-1⚡): Making an incorrect move attempt on the board costs 1 Energy.',
          'Visualization Depth: Choose 1, 2, 3, 4, or 5 moves to calculate in your head before executing the winning move.',
          'Forcing Tactics: Puzzles are filtered for high quality (Rating 1300+).',
          '👁️ Eye Icon (Visual Aid): Toggle ghost dots on pieces moving in the mental sequence.',
          '⏪ Replay Bar: Inspect full step-by-step solutions after completing a puzzle.',
        ],
        tips: [
          'Do not rush: Mentally verify the final position before touching a piece on the board.',
          'Try increasing Visualization Depth up to 4 or 5 moves as your mental vision improves!',
        ],
      ),
    );
  }

  static Future<void> showEnergyInfo(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const ModeInfoDialog(
        title: 'Energy System',
        icon: '⚡',
        objectives: [
          'Track your training attempts and keep your focus sharp.',
        ],
        rules: [
          '⚡ Max Capacity: You have 10 Energy (10/10).',
          '⏳ Automatic Refill: Energy refills back to 10/10 automatically every 60 minutes.',
          '📺 Instant Refill (+10⚡): At 0 energy, watch a short video ad to instantly top up to 10/10!',
          '🎮 Energy usage: Costs 1⚡ ONLY when making a mistake in Stepback/Pathfinder, failing a route, or starting a 60s Coordinates session.',
        ],
        tips: [
          'Navigating, calculating, and solving puzzles correctly costs 0 energy!',
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSectionHeader('🎯 Objective', const Color(0xFF38BDF8)),
            const SizedBox(height: 6),
            ...objectives.map((item) => _buildBulletPoint(item)),
            const SizedBox(height: 16),
            _buildSectionHeader('📜 Rules & Controls', const Color(0xFFF59E0B)),
            const SizedBox(height: 6),
            ...rules.map((item) => _buildBulletPoint(item)),
            const SizedBox(height: 16),
            _buildSectionHeader('💡 Pro Tips', const Color(0xFF10B981)),
            const SizedBox(height: 6),
            ...tips.map((item) => _buildBulletPoint(item)),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Text(
      title,
      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
