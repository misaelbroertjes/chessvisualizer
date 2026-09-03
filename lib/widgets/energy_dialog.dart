import 'dart:async';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/ad_service.dart';

class EnergyDialog extends StatefulWidget {
  final VoidCallback onRefilled;

  const EnergyDialog({super.key, required this.onRefilled});

  static Future<void> show(BuildContext context, {required VoidCallback onRefilled}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => EnergyDialog(onRefilled: onRefilled),
    );
  }

  @override
  State<EnergyDialog> createState() => _EnergyDialogState();
}

class _EnergyDialogState extends State<EnergyDialog> {
  final StorageService _storageService = StorageService();
  final AdService _adService = AdService();

  Timer? _timer;
  int _secondsLeft = 3600;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() async {
    final remaining = await _storageService.getSecondsUntilEnergyReset();
    if (!mounted) return;
    setState(() {
      _secondsLeft = remaining;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        await _storageService.refillEnergy();
        widget.onRefilled();
        if (mounted) Navigator.pop(context);
      } else {
        setState(() {
          _secondsLeft--;
        });
      }
    });
  }

  String _formatTimer(int totalSec) {
    final mins = (totalSec ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSec % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void _watchAdToRefill() {
    _adService.showRewardedAd(
      onUserEarnedReward: () async {
        await _storageService.refillEnergy();
        widget.onRefilled();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚡ +10 Training Attempts Restored! Enjoy!')),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.bolt, color: Color(0xFFF59E0B), size: 28),
          SizedBox(width: 8),
          Text(
            'Limit Reached',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'You have used your 10 hourly training attempts.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_outlined, color: Color(0xFF38BDF8), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Free refill in: ${_formatTimer(_secondsLeft)}',
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.ondemand_video, color: Colors.white),
              label: const Text(
                'Watch Ad (+10 Attempts)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              onPressed: _watchAdToRefill,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }
}
