import 'package:flutter_test/flutter_test.dart';
import 'package:chess_visualization_app/main.dart';

void main() {
  testWidgets('App load smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ChessVisualizationApp());
    expect(find.text('Chess Visualization App'), findsOneWidget);
  });
}
