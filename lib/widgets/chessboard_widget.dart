import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/storage_service.dart';

class BoardThemePalette {
  final String id;
  final String name;
  final String subtitle;
  final Color lightSquare;
  final Color darkSquare;
  final Color borderColor;
  final Color coordOnLight;
  final Color coordOnDark;

  const BoardThemePalette({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.lightSquare,
    required this.darkSquare,
    required this.borderColor,
    required this.coordOnLight,
    required this.coordOnDark,
  });

  static const Map<String, BoardThemePalette> themes = {
    'slate': BoardThemePalette(
      id: 'slate',
      name: 'Slate (Improved Default)',
      subtitle: 'Crisp slate-blue with lighter dark squares for high contrast',
      lightSquare: Color(0xFFE2E8F0),
      darkSquare: Color(0xFF64748B),
      borderColor: Color(0xFF334155),
      coordOnLight: Color(0xFF475569),
      coordOnDark: Color(0xFFE2E8F0),
    ),
    'green': BoardThemePalette(
      id: 'green',
      name: 'Classic Green',
      subtitle: 'Warm cream and tournament green squares',
      lightSquare: Color(0xFFEEEED2),
      darkSquare: Color(0xFF769656),
      borderColor: Color(0xFF4A6332),
      coordOnLight: Color(0xFF5D7842),
      coordOnDark: Color(0xFFEEEED2),
    ),
    'blue': BoardThemePalette(
      id: 'blue',
      name: 'Ocean Blue',
      subtitle: 'Cool ice-white and bright steel-blue squares',
      lightSquare: Color(0xFFDEE3E6),
      darkSquare: Color(0xFF6D92B0),
      borderColor: Color(0xFF3B5973),
      coordOnLight: Color(0xFF4A6E8A),
      coordOnDark: Color(0xFFDEE3E6),
    ),
    'high_contrast': BoardThemePalette(
      id: 'high_contrast',
      name: 'High Contrast',
      subtitle: 'Maximum piece visibility in bright or low-light conditions',
      lightSquare: Color(0xFFFFFFFF),
      darkSquare: Color(0xFF8B9BB4),
      borderColor: Color(0xFF475569),
      coordOnLight: Color(0xFF334155),
      coordOnDark: Color(0xFFFFFFFF),
    ),
  };

  static BoardThemePalette of(String id) => themes[id] ?? themes['slate']!;
}

class ChessboardWidget extends StatelessWidget {
  final Map<String, String> position; // e.g. {'e4': 'wP', 'e1': 'wK'}
  final String orientation; // 'white' or 'black'
  final bool piecesVisible;
  final bool showCoordinates;
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
    this.showCoordinates = true,
    this.selectedSquares = const {},
    this.targetSquares = const {},
    this.dangerSquares = const {},
    this.greenHighlights = const {},
    this.errorSquares = const {},
    this.pieceMarkers = const {},
    this.onSquareTap,
  });

  static Future<void> showThemePicker(BuildContext context) {
    final storage = StorageService();
    return showDialog(
      context: context,
      builder: (ctx) {
        return ValueListenableBuilder<String>(
          valueListenable: storage.boardThemeNotifier,
          builder: (context, currentThemeId, _) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.palette_outlined, color: Color(0xFF38BDF8), size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Board Theme',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: BoardThemePalette.themes.values.map((theme) {
                    final isSelected = theme.id == currentThemeId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          storage.saveBoardTheme(theme.id);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              // 2x2 Mini Board Preview
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: theme.borderColor, width: 1.5),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(child: Container(color: theme.lightSquare)),
                                          Expanded(child: Container(color: theme.darkSquare)),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(child: Container(color: theme.darkSquare)),
                                          Expanded(child: Container(color: theme.lightSquare)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      theme.name,
                                      style: TextStyle(
                                        color: isSelected ? const Color(0xFF38BDF8) : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      theme.subtitle,
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle, color: Color(0xFF38BDF8), size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close', style: TextStyle(color: Colors.grey)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = orientation == 'white'
        ? ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']
        : ['h', 'g', 'f', 'e', 'd', 'c', 'b', 'a'];
    final ranks = orientation == 'white'
        ? ['8', '7', '6', '5', '4', '3', '2', '1']
        : ['1', '2', '3', '4', '5', '6', '7', '8'];

    return ValueListenableBuilder<String>(
      valueListenable: StorageService().boardThemeNotifier,
      builder: (context, themeId, _) {
        final theme = BoardThemePalette.of(themeId);

        return AspectRatio(
          aspectRatio: 1.0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.borderColor, width: 3),
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
                Color bgColor = isLight ? theme.lightSquare : theme.darkSquare;

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
                        if (showCoordinates && fileIdx == 0)
                          Positioned(
                            top: 2,
                            left: 4,
                            child: Text(
                              rank,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isLight ? theme.coordOnLight : theme.coordOnDark,
                              ),
                            ),
                          ),
                        if (showCoordinates && rankIdx == 7)
                          Positioned(
                            bottom: 2,
                            right: 4,
                            child: Text(
                              file,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isLight ? theme.coordOnLight : theme.coordOnDark,
                              ),
                            ),
                          ),

                        // Visualization Dot Aid on empty square
                        if (hasMarker && (!piecesVisible || piece == null))
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFF38BDF8).withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
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

                        // Visualization Dot Aid on occupied square (top-right badge)
                        if (hasMarker && piecesVisible && piece != null)
                          Positioned(
                            top: 3,
                            right: 3,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: const Color(0xFF38BDF8),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF0F172A), width: 1.5),
                              ),
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
      },
    );
  }
}
