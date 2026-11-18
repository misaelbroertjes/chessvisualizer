import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chessboard_widget.dart';

class PuzzleShareData {
  final String puzzleId;
  final int rating;
  final String modeTitle;
  final String? depthLabel;
  final String playerColor; // 'white' or 'black'
  final Map<String, String> boardPosition;
  final Set<String> greenHighlights;
  final String fen; // Exact tactical position (player to move) for Lichess Analysis
  final List<Map<String, String>> movesToCalculate;

  const PuzzleShareData({
    required this.puzzleId,
    required this.rating,
    required this.modeTitle,
    this.depthLabel,
    required this.playerColor,
    required this.boardPosition,
    this.greenHighlights = const {},
    required this.fen,
    this.movesToCalculate = const [],
  });

  static Uri buildLichessAnalysisUri(String fen, String playerColor) {
    final normalizedFen = fen.trim().replaceAll(RegExp(r'\s+'), '_');
    final colorParam = playerColor == 'black' ? 'black' : 'white';
    return Uri.parse('https://lichess.org/analysis/$normalizedFen?color=$colorParam');
  }

  Uri get lichessAnalysisUri => buildLichessAnalysisUri(fen, playerColor);

  String get turnLabel => playerColor == 'black' ? 'Black to move' : 'White to move';

  String buildShareText() {
    final buf = StringBuffer();
    final modeDesc = depthLabel != null ? '$modeTitle ($depthLabel)' : modeTitle;
    buf.writeln('♟️ ChessVisualizer — $modeDesc');
    buf.writeln('Can you find the best move? ($turnLabel)');
    if (movesToCalculate.isNotEmpty) {
      final moveList = movesToCalculate
          .map((m) => m['chessNotation'] ?? m['move'] ?? '')
          .where((s) => s.isNotEmpty)
          .join('  ');
      buf.writeln('Moves in head: $moveList');
    }
    buf.writeln('Puzzle #$puzzleId • Rating $rating');
    buf.write('FEN: $fen');
    return buf.toString();
  }

  String buildClipboardText() {
    final buf = StringBuffer();
    final modeDesc = depthLabel != null ? '$modeTitle ($depthLabel)' : modeTitle;
    buf.writeln('Puzzle #$puzzleId • Rating $rating • $modeDesc');
    buf.writeln('Turn: $turnLabel');
    if (movesToCalculate.isNotEmpty) {
      final moveList = movesToCalculate
          .map((m) => m['chessNotation'] ?? m['move'] ?? '')
          .where((s) => s.isNotEmpty)
          .join('  ');
      buf.writeln('Moves: $moveList');
    }
    buf.writeln('FEN: $fen');
    buf.write('Lichess: ${lichessAnalysisUri.toString()}');
    return buf.toString();
  }
}

class PuzzleShareSheet extends StatefulWidget {
  final PuzzleShareData data;

  const PuzzleShareSheet({super.key, required this.data});

  static Future<void> show(BuildContext context, PuzzleShareData data) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => PuzzleShareSheet(data: data),
    );
  }

  @override
  State<PuzzleShareSheet> createState() => _PuzzleShareSheetState();
}

class _PuzzleShareSheetState extends State<PuzzleShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _isSharingImage = false;

  Future<void> _shareAsImage() async {
    if (_isSharingImage) return;
    setState(() => _isSharingImage = true);

    try {
      // Ensure frame is fully painted before capturing
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Preview not ready');
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) {
        throw Exception('Could not encode PNG');
      }

      final bytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final safeId = widget.data.puzzleId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
      final filePath = '${tempDir.path}${Platform.pathSeparator}chessvisualizer_puzzle_$safeId.png';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null ? (box.localToGlobal(Offset.zero) & box.size) : null;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: widget.data.buildShareText(),
          subject: 'ChessVisualizer Puzzle #${widget.data.puzzleId}',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharingImage = false);
      }
    }
  }

  Future<void> _openInLichess() async {
    final uri = widget.data.lichessAnalysisUri;
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Lichess in browser.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Lichess in browser.')),
        );
      }
    }
  }

  Future<void> _copyFenAndInfo() async {
    await Clipboard.setData(ClipboardData(text: widget.data.buildClipboardText()));
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied Puzzle #${widget.data.puzzleId} & FEN to clipboard!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final maxHeight = MediaQuery.of(context).size.height * 0.9;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Sheet header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.share_rounded, color: Color(0xFF38BDF8), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Share & Analyze Puzzle',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Capturable Shareable Card Preview
              RepaintBoundary(
                key: _cardKey,
                child: _PuzzleShareCard(data: data),
              ),

              const SizedBox(height: 16),

              // Primary Action: Share as Image
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSharingImage ? null : _shareAsImage,
                  icon: _isSharingImage
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.image_outlined, color: Colors.white),
                  label: Text(
                    _isSharingImage ? 'Preparing Image...' : 'Share as Image',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Secondary Row: Open in Lichess + Copy FEN / Bug Info
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF10B981)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _openInLichess,
                        icon: const Icon(
                          Icons.open_in_new_rounded,
                          color: Color(0xFF10B981),
                          size: 18,
                        ),
                        label: const Text(
                          'Lichess Analysis',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF38BDF8)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _copyFenAndInfo,
                        icon: const Icon(
                          Icons.copy_rounded,
                          color: Color(0xFF38BDF8),
                          size: 18,
                        ),
                        label: const Text(
                          'Copy FEN / ID',
                          style: TextStyle(
                            color: Color(0xFF38BDF8),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PuzzleShareCard extends StatelessWidget {
  final PuzzleShareData data;

  const _PuzzleShareCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final isBlack = data.playerColor == 'black';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Branding + Mode Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.remove_red_eye_outlined, color: Color(0xFF6366F1), size: 18),
                  SizedBox(width: 6),
                  Text(
                    'ChessVisualizer',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  data.depthLabel != null
                      ? '${data.modeTitle} • ${data.depthLabel}'
                      : data.modeTitle,
                  style: const TextStyle(
                    color: Color(0xFFA5B4FC),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Turn + Rating + Puzzle ID bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isBlack ? const Color(0xFF0F172A) : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    data.turnLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Text(
                'Puzzle #${data.puzzleId} • Rating ${data.rating}',
                style: const TextStyle(
                  color: Colors.white60,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Chessboard
          ChessboardWidget(
            position: data.boardPosition,
            orientation: data.playerColor,
            greenHighlights: data.greenHighlights,
          ),

          // Optional Stepback visualization moves
          if (data.movesToCalculate.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Visualize these moves in your head:',
                    style: TextStyle(
                      color: Color(0xFF38BDF8),
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(data.movesToCalculate.length, (idx) {
                      final row = data.movesToCalculate[idx];
                      final isBlunder = idx == data.movesToCalculate.length - 1;
                      final moveText = data.movesToCalculate.length >= 6
                          ? (row['chessNotation'] ?? row['move'] ?? '')
                          : '${row['moveNo']}. ${row['move'] ?? ''}';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isBlunder
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                              : const Color(0xFF6366F1).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isBlunder
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.7)
                                : const Color(0xFF6366F1).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          isBlunder ? '$moveText (Blunder)' : moveText,
                          style: TextStyle(
                            color: isBlunder ? const Color(0xFFFBBF24) : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Footer callout
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Can you find the winning move?',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
              Text(
                'ChessVisualizer',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
