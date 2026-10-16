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

  test('StorageService tracks energy and protects active streaks', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();

    final initialEnergy = await storage.getRemainingEnergy();
    expect(initialEnergy, 10);

    final consumed = await storage.consumeEnergy();
    expect(consumed, isTrue);
    expect(await storage.getRemainingEnergy(), 9);

    await storage.recordActivity(true);
    final stats = await storage.loadUserStats();
    expect(stats.streakDays, 1);
    expect(stats.totalPuzzlesSolved, 1);
    expect(stats.eloRating, 1212);

    await storage.saveBoardTheme('green');
    expect(await storage.loadBoardTheme(), 'green');
    expect(BoardThemePalette.of('green').name, 'Classic Green');
  });
}
