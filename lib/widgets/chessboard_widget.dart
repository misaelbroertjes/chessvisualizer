import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ChessboardWidget extends StatelessWidget {
  final Map<String, String> position; // e.g. {'e4': 'wP', 'e1': 'wK'}
  final String orientation; // 'white' or 'black'
  final bool piecesVisible;
  final Set<String> selectedSquares;
  final Set<String> targetSquares;
  final Set<String> dangerSquares;
  final Set<String> greenHighlights;
  final Set<String> errorSquares;
  final Set<String> pieceMarkers; // Visualization dots
  final Function(String square)? onSquareTap;

  const ChessboardWidget({
    super.key,
    required this.position,
    this.orientation = 'white',
    this.piecesVisible = true,
    this.selectedSquares = const {},
    this.targetSquares = const {},
    this.dangerSquares = const {},
    this.greenHighlights = const {},
    this.errorSquares = const {},
    this.pieceMarkers = const {},
    this.onSquareTap,
  });

  @override
  Widget build(BuildContext context) {
    final files = orientation == 'white'
        ? ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']
        : ['h', 'g', 'f', 'e', 'd', 'c', 'b', 'a'];
    final ranks = orientation == 'white'
        ? ['8', '7', '6', '5', '4', '3', '2', '1']
        : ['1', '2', '3', '4', '5', '6', '7', '8'];

    return AspectRatio(
      aspectRatio: 1.0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155), width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: GridView.count(
          crossAxisCount: 8,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(64, (index) {
            final rankIdx = index ~/ 8;
            final fileIdx = index % 8;

            final file = files[fileIdx];
            final rank = ranks[rankIdx];
            final square = '$file$rank';

            // Calculate square color (a1 is dark, h1 is light)
            final isLight = (file.codeUnitAt(0) - 97 + int.parse(rank)) % 2 == 0;
            Color bgColor = isLight ? const Color(0xFFE2E8F0) : const Color(0xFF475569);

            // Apply highlights
            if (errorSquares.contains(square)) {
              bgColor = const Color(0xFFEF4444).withValues(alpha: 0.85);
            } else if (dangerSquares.contains(square)) {
              bgColor = const Color(0xFFDC2626).withValues(alpha: 0.75);
            } else if (selectedSquares.contains(square)) {
              bgColor = const Color(0xFFF59E0B).withValues(alpha: 0.85);
            } else if (targetSquares.contains(square)) {
              bgColor = const Color(0xFF38BDF8).withValues(alpha: 0.85);
            } else if (greenHighlights.contains(square)) {
              bgColor = const Color(0xFF10B981).withValues(alpha: 0.75);
            }

            final piece = position[square];
            final hasMarker = pieceMarkers.contains(square);

            return GestureDetector(
              onTap: () {
                if (onSquareTap != null) {
                  onSquareTap!(square);
                }
              },
              child: Container(
                color: bgColor,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Rank & File Coordinates Label (on edge squares)
                    if (fileIdx == 0)
                      Positioned(
                        top: 2,
                        left: 4,
                        child: Text(
                          rank,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isLight ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                    if (rankIdx == 7)
                      Positioned(
                        bottom: 2,
                        right: 4,
                        child: Text(
                          file,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isLight ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ),

                    // Visualization Dot Aid
                    if (hasMarker && (!piecesVisible || piece == null))
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF94A3B8).withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                      ),


                    // Chess Piece Render
                    if (piecesVisible && piece != null)
                      Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: SvgPicture.asset(
                          'assets/pieces/$piece.svg',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text(
                                piece,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
