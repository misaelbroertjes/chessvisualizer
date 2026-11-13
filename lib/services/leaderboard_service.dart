import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'storage_service.dart';

class LeaderboardEntry {
  final String userId;
  final String nickname;
  final int eloRating;
  final int monthlyXp;
  final String monthKey;
  final int streakDays;
  final int puzzlesSolved;
  final int woodpeckerSets;
  final int coordsHighscore;
  final int pathfinderLevel;
  final bool isClubOnly;

  LeaderboardEntry({
    required this.userId,
    required this.nickname,
    required this.eloRating,
    required this.monthlyXp,
    required this.monthKey,
    required this.streakDays,
    required this.puzzlesSolved,
    required this.woodpeckerSets,
    required this.coordsHighscore,
    required this.pathfinderLevel,
    this.isClubOnly = false,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json, String targetMonthKey) {
    final savedMonth = json['month_key'] as String? ?? targetMonthKey;
    final rawMonthlyXp = (json['monthly_xp'] as num?)?.toInt() ?? 0;
    final rawNick = json['nickname'] as String? ?? 'Player';
    final clubOnly = rawNick.startsWith('\u200B');
    final cleanNick = rawNick.replaceAll('\u200B', '').trim();
    return LeaderboardEntry(
      userId: json['user_id'] as String? ?? '',
      nickname: cleanNick.isEmpty ? 'Player' : cleanNick,
      eloRating: (json['elo_rating'] as num?)?.toInt() ?? 1200,
      monthlyXp: savedMonth == targetMonthKey ? rawMonthlyXp : 0,
      monthKey: savedMonth,
      streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
      puzzlesSolved: (json['puzzles_solved'] as num?)?.toInt() ?? 0,
      woodpeckerSets: (json['woodpecker_sets'] as num?)?.toInt() ?? 0,
      coordsHighscore: (json['coords_highscore'] as num?)?.toInt() ?? 0,
      pathfinderLevel: (json['pathfinder_level'] as num?)?.toInt() ?? 1,
      isClubOnly: clubOnly,
    );
  }
}

class MonthlyChampionSummary {
  final String monthKey;
  final String winnerNickname;
  final int winnerXp;
  final int winnerElo;
  final int participantCount;

  MonthlyChampionSummary({
    required this.monthKey,
    required this.winnerNickname,
    required this.winnerXp,
    required this.winnerElo,
    required this.participantCount,
  });
}

class ClubInfo {
  final String code;
  final String name;
  final String createdBy;

  ClubInfo({
    required this.code,
    required this.name,
    required this.createdBy,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'created_by': createdBy,
      };

  factory ClubInfo.fromJson(Map<String, dynamic> json) => ClubInfo(
        code: (json['code'] as String? ?? '').toUpperCase(),
        name: json['name'] as String? ?? '',
        createdBy: json['created_by'] as String? ?? '',
      );
}

class LeaderboardService {
  static final LeaderboardService _instance = LeaderboardService._internal();
  factory LeaderboardService() => _instance;
  LeaderboardService._internal();

  static const String _supabaseUrl = 'https://xoxapfuotuzkedtdtpya.supabase.co';
  static const String _supabaseAnonKey = 'sb_publishable_6gM-TwXmcYsoZGNs1X7fzg_o09DrFWA';

  static const String _keyUserId = 'lb_user_id';
  static const String _keyDeviceSecret = 'lb_device_secret';
  static const String _keyNickname = 'lb_nickname';
  static const String _keyJoinedClubs = 'lb_joined_clubs';
  static const String _keyHideFromGlobal = 'lb_hide_from_global';

  final StorageService _storageService = StorageService();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await getOrCreateUserId();
    await _getOrCreateDeviceSecret();
    _storageService.onStatsUpdated = () {
      syncMyStats();
    };
  }

  String get currentMonthKey => _storageService.currentMonthKey;

  List<String> getRecentMonthKeys({int count = 6}) {
    final now = DateTime.now();
    final keys = <String>[];
    for (int i = 0; i < count; i++) {
      final dt = DateTime(now.year, now.month - i, 1);
      keys.add("${dt.year}-${dt.month.toString().padLeft(2, '0')}");
    }
    return keys;
  }

  static String formatMonthLabel(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length != 2) return monthKey;
    final year = parts[0];
    final month = int.tryParse(parts[1]) ?? 1;
    const names = [
      'Januari',
      'Februari',
      'Maart',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Augustus',
      'September',
      'Oktober',
      'November',
      'December',
    ];
    final mName = names[(month - 1).clamp(0, 11)];
    return '$mName $year';
  }

  Future<String> getOrCreateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_keyUserId);
    if (id == null || id.isEmpty) {
      final rand = Random.secure();
      final bytes = List<int>.generate(12, (_) => rand.nextInt(256));
      id = 'cv_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      await prefs.setString(_keyUserId, id);
    }
    return id;
  }

  /// Secret token stored ONLY on this device, never exposed in public tables.
  /// Used by PostgreSQL RPC functions to verify ownership before any write.
  Future<String> _getOrCreateDeviceSecret() async {
    final prefs = await SharedPreferences.getInstance();
    var secret = prefs.getString(_keyDeviceSecret);
    if (secret == null || secret.isEmpty) {
      final rand = Random.secure();
      final bytes = List<int>.generate(24, (_) => rand.nextInt(256));
      secret = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_keyDeviceSecret, secret);
    }
    return secret;
  }

  Future<String> getNickname() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyNickname) ?? '';
  }

  static bool isValidNickname(String name) {
    final trimmed = name.trim();
    if (trimmed.length < 2 || trimmed.length > 20) return false;
    final lower = trimmed.toLowerCase();
    const blocked = ['fuck', 'shit', 'kanker', 'hoer', 'lul', 'kut', 'nazi', 'hitler'];
    for (final word in blocked) {
      if (lower.contains(word)) return false;
    }
    return true;
  }

  Future<bool> setNickname(String nickname) async {
    final trimmed = nickname.replaceAll('\u200B', '').trim();
    if (!isValidNickname(trimmed)) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNickname, trimmed);
    await syncMyStats();
    return true;
  }

  /// Whether this player's name and scores should be hidden on the public Global
  /// Leaderboard and only shown inside their joined Chess Clubs (ideal for youth players).
  Future<bool> getHideFromGlobal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHideFromGlobal) ?? false;
  }

  Future<void> setHideFromGlobal(bool hide) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHideFromGlobal, hide);
    await syncMyStats();
  }

  Future<void> leaveClub(String clubCode) async {
    final cleanCode = clubCode.trim().toUpperCase();
    try {
      final userId = await getOrCreateUserId();
      final secret = await _getOrCreateDeviceSecret();
      await http
          .post(
            Uri.parse('$_supabaseUrl/rest/v1/rpc/cv_remove_club_member'),
            headers: _headers(),
            body: json.encode({
              'p_owner_id': userId,
              'p_secret': secret,
              'p_club_code': cleanCode,
              'p_target_user_id': userId,
            }),
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {}

    final clubs = await getJoinedClubs();
    clubs.removeWhere((c) => c.code.toUpperCase() == cleanCode);
    await _saveJoinedClubs(clubs);
  }

  Future<ClubInfo?> refreshClubInfo(String clubCode) async {
    final cleanCode = clubCode.trim().toUpperCase();
    try {
      final uri = Uri.parse(
        '$_supabaseUrl/rest/v1/cv_clubs?code=eq.$cleanCode&select=code,name,created_by&limit=1',
      );
      final resp = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 6));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final List<dynamic> data = json.decode(resp.body) as List<dynamic>;
        if (data.isNotEmpty) {
          final updated = ClubInfo.fromJson(data.first as Map<String, dynamic>);
          final clubs = await getJoinedClubs();
          final idx = clubs.indexWhere((c) => c.code.toUpperCase() == cleanCode);
          if (idx >= 0) {
            clubs[idx] = updated;
            await _saveJoinedClubs(clubs);
          }
          return updated;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<ClubInfo>> getJoinedClubs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyJoinedClubs);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List<dynamic>;
      return list.map((e) => ClubInfo.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveJoinedClubs(List<ClubInfo> clubs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyJoinedClubs, json.encode(clubs.map((c) => c.toJson()).toList()));
  }

  Map<String, String> _headers() {
    return <String, String>{
      'apikey': _supabaseAnonKey,
      'Authorization': 'Bearer $_supabaseAnonKey',
      'Content-Type': 'application/json',
    };
  }

  /// Securely syncs local stats via the hardened `cv_sync_score` RPC function,
  /// which verifies the device's secret token before allowing any update.
  Future<bool> syncMyStats() async {
    try {
      final nickname = await getNickname();
      if (nickname.isEmpty) return false;

      final hideFromGlobal = await getHideFromGlobal();
      final syncedNickname = hideFromGlobal ? '\u200B$nickname' : nickname;

      final userId = await getOrCreateUserId();
      final secret = await _getOrCreateDeviceSecret();
      final stats = await _storageService.loadUserStats();
      final monthKey = _storageService.currentMonthKey;

      final rpcPayload = {
        'p_user_id': userId,
        'p_secret': secret,
        'p_nickname': syncedNickname,
        'p_elo_rating': stats.eloRating.clamp(800, 3000),
        'p_monthly_xp': stats.monthlyXp.clamp(0, 50000),
        'p_month_key': monthKey,
        'p_streak_days': stats.streakDays.clamp(0, 3650),
        'p_puzzles_solved': stats.totalPuzzlesSolved.clamp(0, 200000),
        'p_woodpecker_sets': stats.woodpeckerSetsCompleted.clamp(0, 5000),
        'p_coords_highscore': stats.coordinatesHighScore.clamp(0, 250),
        'p_pathfinder_level': stats.pathfinderLevel.clamp(1, 500),
      };

      final resp = await http
          .post(
            Uri.parse('$_supabaseUrl/rest/v1/rpc/cv_sync_score'),
            headers: _headers(),
            body: json.encode(rpcPayload),
          )
          .timeout(const Duration(seconds: 6));

      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Fetches either the Global Leaderboard (`clubCode == null`) or a Club Leaderboard
  /// for a specific `monthKey` (defaults to current month).
  Future<List<LeaderboardEntry>> fetchLeaderboard({
    String? clubCode,
    String? monthKey,
  }) async {
    final currentMonth = _storageService.currentMonthKey;
    final targetMonth = (monthKey == null || monthKey.isEmpty) ? currentMonth : monthKey;
    final isCurrentMonth = targetMonth == currentMonth;
    final isGlobal = clubCode == null || clubCode.isEmpty;

    final myUserId = await getOrCreateUserId();
    final myNick = await getNickname();
    final hideFromGlobal = await getHideFromGlobal();
    final myStats = await _storageService.loadUserStats();

    final myLocalEntry = LeaderboardEntry(
      userId: myUserId,
      nickname: myNick.isEmpty ? 'You (Set Nickname)' : myNick,
      eloRating: myStats.eloRating,
      monthlyXp: isCurrentMonth ? myStats.monthlyXp : 0,
      monthKey: targetMonth,
      streakDays: myStats.streakDays,
      puzzlesSolved: myStats.totalPuzzlesSolved,
      woodpeckerSets: myStats.woodpeckerSetsCompleted,
      coordsHighscore: myStats.coordinatesHighScore,
      pathfinderLevel: myStats.pathfinderLevel,
      isClubOnly: hideFromGlobal,
    );

    try {
      if (isCurrentMonth) {
        await syncMyStats();
      }

      // 1. If looking at a PAST month, query `cv_monthly_scores`
      if (!isCurrentMonth) {
        Set<String>? clubUserIds;
        if (!isGlobal) {
          clubUserIds = await _fetchClubMemberUserIds(clubCode);
          if (clubUserIds.isEmpty) return [];
        }

        final uri = Uri.parse(
          '$_supabaseUrl/rest/v1/cv_monthly_scores?month_key=eq.$targetMonth&select=*&order=monthly_xp.desc,elo_rating.desc&limit=100',
        );
        final resp = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 6));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final List<dynamic> data = json.decode(resp.body) as List<dynamic>;
          var list = data
              .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>, targetMonth))
              .toList();
          if (isGlobal) {
            list = list.where((e) => !e.isClubOnly && !(hideFromGlobal && e.userId == myUserId)).toList();
          } else if (clubUserIds != null) {
            list = list.where((e) => clubUserIds!.contains(e.userId)).toList();
          }
          return list;
        }
        return [];
      }

      // 2. Current month: Global or Club
      if (isGlobal) {
        final uri = Uri.parse(
          '$_supabaseUrl/rest/v1/cv_profiles?select=*&order=monthly_xp.desc,elo_rating.desc&limit=100',
        );
        final resp = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 6));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final List<dynamic> data = json.decode(resp.body) as List<dynamic>;
          final list = data
              .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>, targetMonth))
              .where((e) => !e.isClubOnly && !(hideFromGlobal && e.userId == myUserId))
              .toList();
          if (!hideFromGlobal && !list.any((e) => e.userId == myUserId)) {
            list.add(myLocalEntry);
          }
          return _withGlobalPacesettersIfNeeded(list, targetMonth);
        }
      } else {
        final cleanCode = clubCode.trim().toUpperCase();
        final uri = Uri.parse(
          '$_supabaseUrl/rest/v1/cv_club_members?club_code=eq.$cleanCode&select=user_id,cv_profiles(*)',
        );
        final resp = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 6));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final List<dynamic> data = json.decode(resp.body) as List<dynamic>;
          final entries = <LeaderboardEntry>[];
          for (final row in data) {
            final map = row as Map<String, dynamic>;
            final profile = map['cv_profiles'];
            if (profile is Map<String, dynamic>) {
              entries.add(LeaderboardEntry.fromJson(profile, targetMonth));
            }
          }
          return entries;
        }
      }
    } catch (_) {}

    if (isCurrentMonth && isGlobal) {
      final fallback = hideFromGlobal ? <LeaderboardEntry>[] : <LeaderboardEntry>[myLocalEntry];
      return _withGlobalPacesettersIfNeeded(fallback, targetMonth);
    }
    return isCurrentMonth ? [myLocalEntry] : [];
  }

  /// Supplements the Global Leaderboard with natural-looking reference players
  /// during the early launch phase. For every real player that joins, one
  /// reference player automatically drops out until >= 12 real players exist.
  List<LeaderboardEntry> _withGlobalPacesettersIfNeeded(
    List<LeaderboardEntry> realEntries,
    String targetMonth,
  ) {
    const int targetPoolSize = 13; // e.g. user + up to 12 others
    if (realEntries.length >= targetPoolSize) {
      return realEntries;
    }

    final dayOfMonth = DateTime.now().day.clamp(1, 31);
    final seeds = <Map<String, dynamic>>[
      {
        'id': 'seed_01',
        'nick': 'Thomas_NL',
        'elo': 1445,
        'dailyXp': 40,
        'baseXp': 25,
        'streak': (dayOfMonth % 9) + 3,
        'solved': 95 + dayOfMonth * 3,
        'wp': 3,
        'coords': 26,
        'pf': 11,
      },
      {
        'id': 'seed_02',
        'nick': 'Sicilian_94',
        'elo': 1390,
        'dailyXp': 35,
        'baseXp': 20,
        'streak': (dayOfMonth % 7) + 2,
        'solved': 82 + dayOfMonth * 3,
        'wp': 2,
        'coords': 24,
        'pf': 9,
      },
      {
        'id': 'seed_03',
        'nick': 'Emma_Chess',
        'elo': 1355,
        'dailyXp': 30,
        'baseXp': 30,
        'streak': (dayOfMonth % 6) + 2,
        'solved': 74 + dayOfMonth * 2,
        'wp': 2,
        'coords': 22,
        'pf': 8,
      },
      {
        'id': 'seed_04',
        'nick': 'RookEndgame',
        'elo': 1320,
        'dailyXp': 28,
        'baseXp': 15,
        'streak': (dayOfMonth % 5) + 1,
        'solved': 64 + dayOfMonth * 2,
        'wp': 2,
        'coords': 21,
        'pf': 8,
      },
      {
        'id': 'seed_05',
        'nick': 'Daan_1998',
        'elo': 1285,
        'dailyXp': 25,
        'baseXp': 20,
        'streak': (dayOfMonth % 5) + 2,
        'solved': 55 + dayOfMonth * 2,
        'wp': 1,
        'coords': 20,
        'pf': 7,
      },
      {
        'id': 'seed_06',
        'nick': 'CaroKann_Fan',
        'elo': 1260,
        'dailyXp': 22,
        'baseXp': 15,
        'streak': (dayOfMonth % 4) + 1,
        'solved': 48 + dayOfMonth * 2,
        'wp': 1,
        'coords': 19,
        'pf': 6,
      },
      {
        'id': 'seed_07',
        'nick': 'Fianchetto',
        'elo': 1235,
        'dailyXp': 20,
        'baseXp': 10,
        'streak': (dayOfMonth % 4) + 1,
        'solved': 41 + dayOfMonth,
        'wp': 1,
        'coords': 18,
        'pf': 6,
      },
      {
        'id': 'seed_08',
        'nick': 'Blitz_Bram',
        'elo': 1215,
        'dailyXp': 18,
        'baseXp': 15,
        'streak': (dayOfMonth % 3) + 1,
        'solved': 36 + dayOfMonth,
        'wp': 1,
        'coords': 17,
        'pf': 5,
      },
      {
        'id': 'seed_09',
        'nick': 'Tactical_Eva',
        'elo': 1190,
        'dailyXp': 15,
        'baseXp': 10,
        'streak': (dayOfMonth % 4) + 1,
        'solved': 29 + dayOfMonth,
        'wp': 0,
        'coords': 16,
        'pf': 5,
      },
      {
        'id': 'seed_10',
        'nick': 'KnightVision',
        'elo': 1165,
        'dailyXp': 13,
        'baseXp': 10,
        'streak': (dayOfMonth % 3) + 1,
        'solved': 24 + dayOfMonth,
        'wp': 0,
        'coords': 15,
        'pf': 4,
      },
      {
        'id': 'seed_11',
        'nick': 'NordicGambit',
        'elo': 1135,
        'dailyXp': 11,
        'baseXp': 5,
        'streak': (dayOfMonth % 2) + 1,
        'solved': 18 + dayOfMonth,
        'wp': 0,
        'coords': 14,
        'pf': 3,
      },
      {
        'id': 'seed_12',
        'nick': 'ZwolleChess',
        'elo': 1095,
        'dailyXp': 8,
        'baseXp': 10,
        'streak': 1,
        'solved': 12 + dayOfMonth,
        'wp': 0,
        'coords': 12,
        'pf': 2,
      },
    ];

    final needed = (targetPoolSize - realEntries.length).clamp(0, seeds.length);
    final combined = List<LeaderboardEntry>.from(realEntries);

    for (int i = 0; i < needed; i++) {
      final s = seeds[i];
      final rawXp = (s['baseXp'] as int) + (dayOfMonth - 1) * (s['dailyXp'] as int);
      final roundedXp = (rawXp ~/ 5) * 5;
      combined.add(
        LeaderboardEntry(
          userId: s['id'] as String,
          nickname: s['nick'] as String,
          eloRating: s['elo'] as int,
          monthlyXp: roundedXp,
          monthKey: targetMonth,
          streakDays: s['streak'] as int,
          puzzlesSolved: s['solved'] as int,
          woodpeckerSets: s['wp'] as int,
          coordsHighscore: s['coords'] as int,
          pathfinderLevel: s['pf'] as int,
        ),
      );
    }

    return combined;
  }

  Future<Set<String>> _fetchClubMemberUserIds(String clubCode) async {
    final cleanCode = clubCode.trim().toUpperCase();
    final uri = Uri.parse(
      '$_supabaseUrl/rest/v1/cv_club_members?club_code=eq.$cleanCode&select=user_id',
    );
    final resp = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 6));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final List<dynamic> data = json.decode(resp.body) as List<dynamic>;
      return data
          .map((e) => (e as Map<String, dynamic>)['user_id'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
    }
    return {};
  }

  /// Fetches Hall of Fame (past monthly winners + their scores) for either Global or a specific Club!
  Future<List<MonthlyChampionSummary>> fetchMonthlyChampions({String? clubCode}) async {
    try {
      Set<String>? clubUserIds;
      if (clubCode != null && clubCode.isNotEmpty) {
        clubUserIds = await _fetchClubMemberUserIds(clubCode);
        if (clubUserIds.isEmpty) return [];
      }

      final uri = Uri.parse(
        '$_supabaseUrl/rest/v1/cv_monthly_scores?select=*&order=month_key.desc,monthly_xp.desc',
      );
      final resp = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 6));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return [];

      final List<dynamic> rows = json.decode(resp.body) as List<dynamic>;
      final Map<String, List<Map<String, dynamic>>> byMonth = {};

      for (final raw in rows) {
        final map = raw as Map<String, dynamic>;
        final mKey = map['month_key'] as String? ?? '';
        final uId = map['user_id'] as String? ?? '';
        final rawNick = map['nickname'] as String? ?? 'Player';
        final isClubOnly = rawNick.startsWith('\u200B');
        final xp = (map['monthly_xp'] as num?)?.toInt() ?? 0;
        if (mKey.isEmpty || mKey == currentMonthKey || xp <= 0) continue;
        if (clubUserIds == null && isClubOnly) continue;
        if (clubUserIds != null && !clubUserIds.contains(uId)) continue;
        byMonth.putIfAbsent(mKey, () => []).add(map);
      }

      final summaries = <MonthlyChampionSummary>[];
      final sortedMonths = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
      for (final mKey in sortedMonths.take(6)) {
        final list = byMonth[mKey]!;
        list.sort(
          (a, b) => ((b['monthly_xp'] as num?) ?? 0).compareTo((a['monthly_xp'] as num?) ?? 0),
        );
        final top = list.first;
        final cleanWinner = (top['nickname'] as String? ?? 'Player').replaceAll('\u200B', '').trim();
        summaries.add(
          MonthlyChampionSummary(
            monthKey: mKey,
            winnerNickname: cleanWinner.isEmpty ? 'Player' : cleanWinner,
            winnerXp: (top['monthly_xp'] as num?)?.toInt() ?? 0,
            winnerElo: (top['elo_rating'] as num?)?.toInt() ?? 1200,
            participantCount: list.length,
          ),
        );
      }
      return summaries;
    } catch (_) {
      return [];
    }
  }

  /// Creates a new Chess Club / Friend Group via the secured `cv_manage_club` RPC.
  Future<ClubInfo?> createClub(String clubName) async {
    final trimmed = clubName.trim();
    if (!isValidNickname(trimmed)) return null;

    final userId = await getOrCreateUserId();
    final secret = await _getOrCreateDeviceSecret();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    final prefix = trimmed
        .replaceAll(RegExp(r'[^A-Za-z]'), '')
        .toUpperCase()
        .padRight(2, 'C')
        .substring(0, 2);
    final suffix = List.generate(4, (_) => chars[rand.nextInt(chars.length)]).join();
    final code = '$prefix-$suffix';

    try {
      // Ensure user has a profile first (even if nickname wasn't set yet, use 'Player')
      final nick = await getNickname();
      if (nick.isEmpty) {
        await setNickname('Player_${userId.substring(3, 7)}');
      } else {
        await syncMyStats();
      }

      final resp = await http
          .post(
            Uri.parse('$_supabaseUrl/rest/v1/rpc/cv_create_or_join_club'),
            headers: _headers(),
            body: json.encode({
              'p_user_id': userId,
              'p_secret': secret,
              'p_club_code': code,
              'p_club_name': trimmed,
              'p_is_create': true,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }

      final club = ClubInfo(code: code, name: trimmed, createdBy: userId);
      final existing = await getJoinedClubs();
      if (!existing.any((c) => c.code == code)) {
        existing.add(club);
        await _saveJoinedClubs(existing);
      }
      return club;
    } catch (_) {
      return null;
    }
  }

  /// Joins an existing Chess Club / Friend Group using its invite code via secured RPC.
  Future<ClubInfo?> joinClubByCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.length < 3 || code.length > 12) return null;

    final userId = await getOrCreateUserId();
    final secret = await _getOrCreateDeviceSecret();

    try {
      final nick = await getNickname();
      if (nick.isEmpty) {
        await setNickname('Player_${userId.substring(3, 7)}');
      } else {
        await syncMyStats();
      }

      final resp = await http
          .post(
            Uri.parse('$_supabaseUrl/rest/v1/rpc/cv_create_or_join_club'),
            headers: _headers(),
            body: json.encode({
              'p_user_id': userId,
              'p_secret': secret,
              'p_club_code': code,
              'p_club_name': '',
              'p_is_create': false,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final dynamic decoded = json.decode(resp.body);
      if (decoded is! Map<String, dynamic>) return null;

      final club = ClubInfo.fromJson(decoded);
      if (club.code.isEmpty) return null;

      final existing = await getJoinedClubs();
      if (!existing.any((c) => c.code == club.code)) {
        existing.add(club);
        await _saveJoinedClubs(existing);
      }
      return club;
    } catch (_) {
      return null;
    }
  }

  /// Allows a club creator (e.g. chess trainer) to remove a member from their club,
  /// verified on the server by checking `p_secret` and `cv_clubs.created_by`.
  Future<bool> removeMemberFromClub(String clubCode, String memberUserId) async {
    try {
      final userId = await getOrCreateUserId();
      final secret = await _getOrCreateDeviceSecret();
      final resp = await http
          .post(
            Uri.parse('$_supabaseUrl/rest/v1/rpc/cv_remove_club_member'),
            headers: _headers(),
            body: json.encode({
              'p_owner_id': userId,
              'p_secret': secret,
              'p_club_code': clubCode,
              'p_target_user_id': memberUserId,
            }),
          )
          .timeout(const Duration(seconds: 6));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
