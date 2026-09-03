import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/puzzle.dart';

class PuzzleService {
  static final PuzzleService _instance = PuzzleService._internal();
  factory PuzzleService() => _instance;
  PuzzleService._internal();

  List<Puzzle> _allPuzzles = [];
  bool _isLoaded = false;

  Future<void> loadPuzzles() async {
    if (_isLoaded) return;
    try {
      final jsonString = await rootBundle.loadString('assets/data/puzzles.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      _allPuzzles = jsonList.map((e) => Puzzle.fromJson(e as Map<String, dynamic>)).toList();
      _isLoaded = true;
    } catch (e) {
      // Fallback empty list or print error
      _allPuzzles = [];
    }
  }

  List<Puzzle> getFilteredPuzzles({
    int minRating = 1300,
    int maxRating = 2800,
    bool forcingOnly = true,
  }) {
    if (_allPuzzles.isEmpty) return [];

    return _allPuzzles.where((p) {
      if (p.rating < minRating || p.rating > maxRating) return false;
      if (forcingOnly && p.forcingScore < 2) return false;
      return true;
    }).toList();
  }

  Puzzle? getRandomPuzzle({
    int minRating = 1300,
    int maxRating = 2800,
    bool forcingOnly = true,
  }) {
    final list = getFilteredPuzzles(
      minRating: minRating,
      maxRating: maxRating,
      forcingOnly: forcingOnly,
    );
    if (list.isEmpty) return _allPuzzles.isNotEmpty ? _allPuzzles.first : null;
    list.shuffle();
    return list.first;
  }
}

