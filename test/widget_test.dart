import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chess_visualization_app/widgets/chessboard_widget.dart';
import 'package:chess_visualization_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ChessboardWidget renders coordinates and hides them when disabled', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChessboardWidget(
            position: {},
            showCoordinates: true,
          ),
        ),
      ),
    );

    expect(find.text('a'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChessboardWidget(
            position: {},
            showCoordinates: false,
          ),
        ),
      ),
    );

    expect(find.text('a'), findsNothing);
    expect(find.text('8'), findsNothing);
  });

  test('StorageService tracks energy, realistic ELO, and monthly XP', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();

    final initialEnergy = await storage.getRemainingEnergy();
    expect(initialEnergy, 10);

    final consumed = await storage.consumeEnergy();
    expect(consumed, isTrue);
    expect(await storage.getRemainingEnergy(), 9);

    final deltaWin = await storage.recordRatedPuzzleSuccess(
      puzzleRating: 1200,
      visualizationDepth: 1,
    );
    expect(deltaWin, 14);
    var stats = await storage.loadUserStats();
    expect(stats.streakDays, 1);
    expect(stats.totalPuzzlesSolved, 1);
    expect(stats.eloRating, 1214);
    expect(stats.monthlyXp, greaterThan(0));

    // Mistake deducts ELO and subsequent completion does not add ELO back
    final deltaLoss = await storage.recordRatedPuzzleMistake(
      puzzleRating: 1214,
      visualizationDepth: 1,
    );
    expect(deltaLoss, -14);
    await storage.recordPuzzleCompletionWithoutElo(xpEarned: 8, countAttempt: false);
    stats = await storage.loadUserStats();
    expect(stats.eloRating, 1200);
    expect(stats.totalPuzzlesSolved, 2);

    // Non-ELO modes (Coordinates / Pathfinder) award XP without altering ELO
    await storage.recordModeTraining(xpEarned: 20);
    stats = await storage.loadUserStats();
    expect(stats.eloRating, 1200);

    await storage.saveBoardTheme('green');
    expect(await storage.loadBoardTheme(), 'green');
    expect(BoardThemePalette.of('green').name, 'Classic Green');
  });
}
