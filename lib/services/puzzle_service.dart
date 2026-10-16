import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/puzzle.dart';

List<Puzzle> _parsePuzzlesJson(String jsonString) {
  final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
  return jsonList.map((e) => Puzzle.fromJson(e as Map<String, dynamic>)).toList();
}

class PuzzleService {
  static final PuzzleService _instance = PuzzleService._internal();
  factory PuzzleService() => _instance;
  PuzzleService._internal();

  final Random _random = Random();
  List<Puzzle> _allPuzzles = [];
  final Set<String> _recentPuzzleIds = {};
  bool _isLoaded = false;

  Future<void> loadPuzzles() async {
    if (_isLoaded) return;
    try {
      final jsonString = await rootBundle.loadString('assets/data/puzzles.json');
      _allPuzzles = await compute(_parsePuzzlesJson, jsonString);
      _isLoaded = true;
    } catch (e) {
      _allPuzzles = [];
    }
  }

  List<Puzzle> getFilteredPuzzles({
    int minRating = 800,
    int maxRating = 2800,
    bool forcingOnly = true,
    int minPreMoves = 0,
  }) {
    if (_allPuzzles.isEmpty) return [];

    return _allPuzzles.where((p) {
      if (p.rating < minRating || p.rating > maxRating) return false;
      if (forcingOnly && p.forcingScore < 2) return false;
      if (minPreMoves > 0) {
        final available = p.gameMoves.isNotEmpty ? (p.ply - 1) : p.preMoves.length;
        if (available < minPreMoves) return false;
      }
      return true;
    }).toList();
  }

  Puzzle? getRandomPuzzle({
    int minRating = 800,
    int maxRating = 2800,
    bool forcingOnly = true,
    int minPreMoves = 0,
  }) {
    var list = getFilteredPuzzles(
      minRating: minRating,
      maxRating: maxRating,
      forcingOnly: forcingOnly,
      minPreMoves: minPreMoves,
    );
    if (list.isEmpty) {
      list = getFilteredPuzzles(
        minRating: 800,
        maxRating: 2800,
        forcingOnly: forcingOnly,
        minPreMoves: minPreMoves,
      );
    }
    if (list.isEmpty) {
      list = getFilteredPuzzles(
        minRating: 800,
        maxRating: 2800,
        forcingOnly: false,
        minPreMoves: minPreMoves,
      );
    }
    if (list.isEmpty) {
      return _allPuzzles.isNotEmpty
          ? _allPuzzles[_random.nextInt(_allPuzzles.length)]
          : null;
    }

    final unseen = list.where((p) => !_recentPuzzleIds.contains(p.id)).toList();
    final pool = unseen.isNotEmpty ? unseen : list;
    if (unseen.isEmpty) {
      _recentPuzzleIds.clear();
    }

    final chosen = pool[_random.nextInt(pool.length)];
    _recentPuzzleIds.add(chosen.id);
    return chosen;
  }
}


