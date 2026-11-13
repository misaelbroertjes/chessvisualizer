import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/leaderboard_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final LeaderboardService _leaderboardService = LeaderboardService();

  String _myUserId = '';
  String _myNickname = '';
  bool _hideFromGlobal = false;
  bool _isLoading = true;

  List<ClubInfo> _joinedClubs = [];
  ClubInfo? _selectedClub; // null == Global Leaderboard

  late List<String> _availableMonths;
  int _selectedMonthIndex = 0; // 0 == current month, 1 == last month, etc.

  String _sortBy = 'monthly_xp'; // 'monthly_xp', 'elo'
  List<LeaderboardEntry> _entries = [];
  List<MonthlyChampionSummary> _champions = [];

  @override
  void initState() {
    super.initState();
    _availableMonths = _leaderboardService.getRecentMonthKeys(count: 6);
    _initAndLoad();
  }

  String get _selectedMonthKey => _availableMonths[_selectedMonthIndex];
  bool get _isViewingCurrentMonth => _selectedMonthIndex == 0;

  Future<void> _initAndLoad() async {
    await _leaderboardService.initialize();
    final uid = await _leaderboardService.getOrCreateUserId();
    final nick = await _leaderboardService.getNickname();
    final hideGlobal = await _leaderboardService.getHideFromGlobal();
    final clubs = await _leaderboardService.getJoinedClubs();

    if (!mounted) return;
    setState(() {
      _myUserId = uid;
      _myNickname = nick;
      _hideFromGlobal = hideGlobal;
      _joinedClubs = clubs;
    });

    await _refreshEntries();

    if (nick.isEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showEditNicknameDialog(firstTime: true);
      });
    }
  }

  Future<void> _refreshEntries() async {
    setState(() {
      _isLoading = true;
    });
    ClubInfo? activeClub = _selectedClub;
    if (activeClub != null) {
      final refreshed = await _leaderboardService.refreshClubInfo(activeClub.code);
      if (refreshed != null) {
        activeClub = refreshed;
      }
    }
    final clubs = await _leaderboardService.getJoinedClubs();
    final list = await _leaderboardService.fetchLeaderboard(
      clubCode: activeClub?.code,
      monthKey: _selectedMonthKey,
    );
    final champs = await _leaderboardService.fetchMonthlyChampions(
      clubCode: activeClub?.code,
    );
    if (!mounted) return;
    setState(() {
      _joinedClubs = clubs;
      _selectedClub = activeClub;
      _entries = list;
      _champions = champs;
      _isLoading = false;
    });
  }

  List<LeaderboardEntry> get _sortedEntries {
    final copy = List<LeaderboardEntry>.from(_entries);
    copy.sort((a, b) {
      if (_sortBy == 'elo') {
        final cmp = b.eloRating.compareTo(a.eloRating);
        return cmp != 0 ? cmp : b.monthlyXp.compareTo(a.monthlyXp);
      } else {
        final cmp = b.monthlyXp.compareTo(a.monthlyXp);
        return cmp != 0 ? cmp : b.eloRating.compareTo(a.eloRating);
      }
    });
    return copy;
  }

  void _showEditNicknameDialog({bool firstTime = false}) {
    final controller = TextEditingController(text: _myNickname);
    bool tempHideGlobal = _hideFromGlobal;
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                firstTime ? '👋 Nickname & Privacy' : '✏️ Nickname & Privacy',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No account or email needed! Pick a nickname for the Monthly & Chess Club Leaderboards:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLength: 20,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g. Magnus_NL',
                      hintStyle: const TextStyle(color: Colors.grey),
                      errorText: errorText,
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: tempHideGlobal ? const Color(0xFFF59E0B) : const Color(0xFF334155),
                      ),
                    ),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      dense: true,
                      activeThumbColor: const Color(0xFFF59E0B),
                      title: const Text(
                        'Hide my name on Global list',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Only show my name inside my joined Chess Clubs (safe for youth players).',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                      value: tempHideGlobal,
                      onChanged: (val) {
                        setDialogState(() {
                          tempHideGlobal = val;
                        });
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                  onPressed: () async {
                    await _leaderboardService.setHideFromGlobal(tempHideGlobal);
                    final trimmed = controller.text.trim();
                    if (trimmed.isNotEmpty) {
                      final ok = await _leaderboardService.setNickname(trimmed);
                      if (!ok) {
                        setDialogState(() {
                          errorText = 'Please enter a valid nickname (2-20 chars).';
                        });
                        return;
                      }
                    }
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    final updatedNick = await _leaderboardService.getNickname();
                    final updatedHide = await _leaderboardService.getHideFromGlobal();
                    setState(() {
                      _myNickname = updatedNick;
                      _hideFromGlobal = updatedHide;
                    });
                    _refreshEntries();
                  },
                  child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmAndRemoveMember(LeaderboardEntry member) async {
    final club = _selectedClub;
    if (club == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove Member from Club?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        content: Text(
          'Are you sure you want to remove "${member.nickname}" from ${club.name}?',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await _leaderboardService.removeMemberFromClub(club.code, member.userId);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${member.nickname} removed from ${club.name}.')),
        );
        _refreshEntries();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove member. Please check your connection.')),
        );
      }
    }
  }

  void _showManageClubMembersDialog() {
    final club = _selectedClub;
    if (club == null) return;
    final otherMembers = _sortedEntries.where((e) => e.userId != _myUserId).toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '👥 Manage ${club.name}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: otherMembers.isEmpty
                ? Text(
                    'You are the creator of ${club.name} (Code: ${club.code}).\n\nAs soon as other players join with your invite code, they will appear here so you can remove anyone from your club at any time.',
                    style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: otherMembers.length,
                      separatorBuilder: (_, __) => const Divider(color: Color(0xFF334155), height: 12),
                      itemBuilder: (context, i) {
                        final m = otherMembers[i];
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.nickname,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  Text(
                                    'ELO ${m.eloRating} • ${m.monthlyXp} XP',
                                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _confirmAndRemoveMember(m);
                              },
                              icon: const Icon(Icons.person_remove_outlined, color: Color(0xFFEF4444), size: 16),
                              label: const Text(
                                'Remove',
                                style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _confirmAndLeaveClub(club);
              },
              icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 16),
              label: const Text('Verlaat club', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: Colors.white70)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmAndLeaveClub(ClubInfo club) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Club verlaten?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        content: Text(
          'Weet je zeker dat je "${club.name}" wilt verlaten? Je kunt later altijd weer deelnemen met code ${club.code}.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verlaat club', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _leaderboardService.leaveClub(club.code);
      final updatedClubs = await _leaderboardService.getJoinedClubs();
      if (!mounted) return;
      setState(() {
        _joinedClubs = updatedClubs;
        _selectedClub = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Je hebt ${club.name} verlaten.')),
      );
      _refreshEntries();
    }
  }

  void _showJoinClubDialog() {
    final controller = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                '♟️ Join Chess Club / Group',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the club code shared by your chess trainer or friend:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                    decoration: InputDecoration(
                      hintText: 'e.g. SC-4829',
                      hintStyle: const TextStyle(color: Colors.grey),
                      errorText: errorText,
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  onPressed: () async {
                    final club = await _leaderboardService.joinClubByCode(controller.text);
                    if (club == null) {
                      setDialogState(() {
                        errorText = 'Club code not found. Check the code and try again.';
                      });
                      return;
                    }
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    final clubs = await _leaderboardService.getJoinedClubs();
                    setState(() {
                      _joinedClubs = clubs;
                      _selectedClub = club;
                    });
                    _refreshEntries();
                  },
                  child: const Text('Join Club', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateClubDialog() {
    final controller = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                '🏆 Create Club / Friends Group',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create a private leaderboard for your chess club, youth group, or friends. You will get an invite code to share!',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLength: 24,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g. SV Utrecht Jeugd',
                      hintStyle: const TextStyle(color: Colors.grey),
                      errorText: errorText,
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                  onPressed: () async {
                    final club = await _leaderboardService.createClub(controller.text);
                    if (club == null) {
                      setDialogState(() {
                        errorText = 'Could not create club. Enter a valid name (2-20 chars).';
                      });
                      return;
                    }
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    final clubs = await _leaderboardService.getJoinedClubs();
                    setState(() {
                      _joinedClubs = clubs;
                      _selectedClub = club;
                    });
                    _refreshEntries();
                  },
                  child: const Text('Create', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    final sorted = _sortedEntries;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text(
          'Clubs & Leaderboard',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Color(0xFF38BDF8)),
            tooltip: 'Edit Nickname',
            onPressed: () => _showEditNicknameDialog(firstTime: false),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: RefreshIndicator(
          onRefresh: _refreshEntries,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16.0, 14.0, 16.0, 32.0),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Club / Group Filter Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'LEADERBOARD GROUP',
                    style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: _showJoinClubDialog,
                        icon: const Icon(Icons.group_add_outlined, size: 16, color: Color(0xFF10B981)),
                        label: const Text('Join Code', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: _showCreateClubDialog,
                        icon: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF38BDF8)),
                        label: const Text('New Club', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('🌍 Global'),
                      selected: _selectedClub == null,
                      selectedColor: const Color(0xFF6366F1),
                      backgroundColor: const Color(0xFF1E293B),
                      labelStyle: TextStyle(
                        color: _selectedClub == null ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) {
                        setState(() => _selectedClub = null);
                        _refreshEntries();
                      },
                    ),
                    ..._joinedClubs.map((club) {
                      final isSel = _selectedClub?.code == club.code;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: ChoiceChip(
                          label: Text('♟️ ${club.name} (${club.code})'),
                          selected: isSel,
                          selectedColor: const Color(0xFF10B981),
                          backgroundColor: const Color(0xFF1E293B),
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (_) {
                            setState(() => _selectedClub = club);
                            _refreshEntries();
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),

              if (_selectedClub != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedClub!.name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Invite Code: ${_selectedClub!.code}',
                              style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_selectedClub!.createdBy == _myUserId) ...[
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFEF4444)),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                              ),
                              icon: const Icon(Icons.group_remove_outlined, size: 15, color: Color(0xFFEF4444)),
                              label: const Text('Leden', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: _showManageClubMembersDialog,
                            ),
                            const SizedBox(width: 6),
                          ],
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF10B981)),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            icon: const Icon(Icons.copy, size: 15, color: Color(0xFF10B981)),
                            label: const Text('Copy Code', style: TextStyle(color: Color(0xFF10B981), fontSize: 12)),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _selectedClub!.code));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Club code ${_selectedClub!.code} copied! Share it with your club!')),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Verlaat club',
                            icon: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFFEF4444)),
                            onPressed: () => _confirmAndLeaveClub(_selectedClub!),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Month Selector Bar (Browse Current Month & Past Months inside Club or Global!)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Previous Month',
                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                      onPressed: _selectedMonthIndex < _availableMonths.length - 1
                          ? () {
                              setState(() {
                                _selectedMonthIndex++;
                                _sortBy = 'monthly_xp';
                              });
                              _refreshEntries();
                            }
                          : null,
                    ),
                    Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_month, size: 15, color: Color(0xFF38BDF8)),
                            const SizedBox(width: 6),
                            Text(
                              LeaderboardService.formatMonthLabel(_selectedMonthKey),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (_isViewingCurrentMonth) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'LIVE',
                                  style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'ARCHIVE',
                                  style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          _selectedClub != null
                              ? '${_selectedClub!.name} Monthly Standings'
                              : 'Global Monthly Standings',
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Next Month',
                      icon: const Icon(Icons.chevron_right, color: Colors.white),
                      onPressed: _selectedMonthIndex > 0
                          ? () {
                              setState(() {
                                _selectedMonthIndex--;
                              });
                              _refreshEntries();
                            }
                          : null,
                    ),
                  ],
                ),
              ),

              // Hall of Fame: Past Monthly Winners for this Club (or Global)
              if (_champions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.workspace_premium, color: Color(0xFFF59E0B), size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _selectedClub != null
                                ? '🏆 ${_selectedClub!.name} — Winnaars Afgelopen Maanden'
                                : '🏆 Global — Winnaars Afgelopen Maanden',
                            style: const TextStyle(
                              color: Color(0xFFF59E0B),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _champions.map((champ) {
                            final idxInMonths = _availableMonths.indexOf(champ.monthKey);
                            final isSelectedMonth = _selectedMonthKey == champ.monthKey;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: idxInMonths >= 0
                                    ? () {
                                        setState(() {
                                          _selectedMonthIndex = idxInMonths;
                                        });
                                        _refreshEntries();
                                      }
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelectedMonth
                                        ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                                        : const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelectedMonth
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFF334155),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        LeaderboardService.formatMonthLabel(champ.monthKey),
                                        style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '🥇 ${champ.winnerNickname}',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      Text(
                                        '${champ.winnerXp} XP • ELO ${champ.winnerElo}',
                                        style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // Ranking Metric Selector (Monthly XP & ELO Rating only, with extra space)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _buildSortTab('monthly_xp', '🔥 Monthly XP'),
                    const SizedBox(width: 6),
                    _buildSortTab('elo', '⭐ Rating (ELO)'),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(36.0),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))),
                )
              else if (sorted.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.history_toggle_off, color: Colors.grey, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        'Geen scores gevonden voor ${LeaderboardService.formatMonthLabel(_selectedMonthKey)}.',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                ..._buildLeaderboardRows(sorted),
            ],
          ),
        ),
      ),
      ),
    );
  }

  List<Widget> _buildLeaderboardRows(List<LeaderboardEntry> sorted) {
    // In a Club, always show all club members.
    if (_selectedClub != null) {
      return List.generate(sorted.length, (idx) => _buildEntryRow(sorted[idx], idx + 1));
    }

    // On Global: show Top 5 + your own position with 5 above and 5 below you.
    final myIndex = sorted.indexWhere((e) => e.userId == _myUserId);
    final widgets = <Widget>[];

    if (myIndex < 0) {
      final topCount = sorted.length < 5 ? sorted.length : 5;
      for (int i = 0; i < topCount; i++) {
        widgets.add(_buildEntryRow(sorted[i], i + 1));
      }
      return widgets;
    }

    if (myIndex < 5) {
      // User is inside Top 5: show at least Top 5, extended so 5 below the user are also visible
      final endExclusive = (myIndex + 6 > 5 ? myIndex + 6 : 5).clamp(0, sorted.length);
      for (int i = 0; i < endExclusive; i++) {
        widgets.add(_buildEntryRow(sorted[i], i + 1));
      }
      return widgets;
    }

    // User is outside Top 5:
    // 1. Render Top 5
    final topCount = sorted.length < 5 ? sorted.length : 5;
    for (int i = 0; i < topCount; i++) {
      widgets.add(_buildEntryRow(sorted[i], i + 1));
    }

    // 2. Render window around user: 5 above (not overlapping Top 5) and 5 below
    final startIdx = (myIndex - 5) > 5 ? (myIndex - 5) : 5;
    final endExclusive = (myIndex + 6).clamp(0, sorted.length);

    widgets.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            const Expanded(child: Divider(color: Color(0xFF334155), thickness: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text(
                '• • •  Your Position (#${myIndex + 1})  • • •',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const Expanded(child: Divider(color: Color(0xFF334155), thickness: 1)),
          ],
        ),
      ),
    );

    for (int i = startIdx; i < endExclusive; i++) {
      widgets.add(_buildEntryRow(sorted[i], i + 1));
    }

    return widgets;
  }

  Widget _buildEntryRow(LeaderboardEntry entry, int rank) {
    final isMe = entry.userId == _myUserId;
    final canRemove = _selectedClub != null &&
        _selectedClub!.createdBy == _myUserId &&
        !isMe;

    String medal = '#$rank';
    if (rank == 1) medal = '🥇';
    if (rank == 2) medal = '🥈';
    if (rank == 3) medal = '🥉';

    String primaryValue = '${entry.monthlyXp} XP';
    String subValue = 'ELO ${entry.eloRating} • 🔥 ${entry.streakDays}d streak';
    if (_sortBy == 'elo') {
      primaryValue = '${entry.eloRating}';
      subValue = '${entry.monthlyXp} Monthly XP • ${entry.puzzlesSolved} solved';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe
            ? const Color(0xFF6366F1).withValues(alpha: 0.2)
            : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? const Color(0xFF6366F1) : const Color(0xFF334155),
          width: isMe ? 1.8 : 1.0,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              medal,
              style: TextStyle(
                fontSize: rank <= 3 ? 20 : 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.nickname,
                        style: TextStyle(
                          color: isMe ? const Color(0xFF38BDF8) : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'YOU',
                          style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subValue,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            primaryValue,
            style: const TextStyle(
              color: Color(0xFF10B981),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          if (canRemove)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.person_remove_outlined, color: Color(0xFFEF4444), size: 19),
              tooltip: 'Remove from club',
              onPressed: () => _confirmAndRemoveMember(entry),
            ),
        ],
      ),
    );
  }

  Widget _buildSortTab(String key, String label) {
    final selected = _sortBy == key;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _sortBy = key),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF6366F1) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }
}
