/// Minimal value types for The Blue Alliance API v3 responses.
///
/// Field names mirror TBA's snake_case JSON. We only model the fields the app
/// currently uses; new fields can be added as features need them.
class TbaTeam {
  TbaTeam({
    required this.key,
    required this.teamNumber,
    required this.nickname,
    required this.name,
    this.city,
    this.stateProv,
    this.country,
  });

  factory TbaTeam.fromJson(Map<String, dynamic> json) {
    return TbaTeam(
      key: json['key'] as String,
      teamNumber: (json['team_number'] as num).toInt(),
      nickname: (json['nickname'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      city: json['city'] as String?,
      stateProv: json['state_prov'] as String?,
      country: json['country'] as String?,
    );
  }

  /// TBA team_key, e.g. `frc1234`.
  final String key;
  final int teamNumber;
  final String nickname;
  final String name;
  final String? city;
  final String? stateProv;
  final String? country;

  String get displayLocation {
    final parts = <String>[
      if (city != null && city!.isNotEmpty) city!,
      if (stateProv != null && stateProv!.isNotEmpty) stateProv!,
      if (country != null && country!.isNotEmpty) country!,
    ];
    return parts.join(', ');
  }
}

/// An FRC event from TBA, modeled with the fields the Statbotics fallback
/// needs (#512): enough to fill the event picker and name the event.
class TbaEvent {
  const TbaEvent({
    required this.key,
    required this.name,
    required this.year,
    this.week,
    this.country,
    this.stateProv,
    this.startDate,
    this.endDate,
  });

  factory TbaEvent.fromJson(Map<String, dynamic> json) {
    final year = json['year'];
    final week = json['week'];
    return TbaEvent(
      key: (json['key'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      year: year is num ? year.toInt() : 0,
      // TBA weeks are zero-based; Statbotics (and humans) count from 1.
      week: week is num ? week.toInt() + 1 : null,
      country: json['country'] as String?,
      stateProv: json['state_prov'] as String?,
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
    );
  }

  final String key;
  final String name;
  final int year;
  final int? week;
  final String? country;
  final String? stateProv;
  final String? startDate;
  final String? endDate;
}

/// One match from a TBA event schedule, with alliances resolved to plain
/// team numbers. Used by the Statbotics schedule fallback (#512).
class TbaScheduleMatch {
  const TbaScheduleMatch({
    required this.key,
    required this.compLevel,
    required this.matchNumber,
    required this.redTeams,
    required this.blueTeams,
  });

  factory TbaScheduleMatch.fromJson(Map<String, dynamic> json) {
    List<int> extractTeams(Object? alliance) {
      if (alliance is! Map) {
        return const <int>[];
      }
      final keys = alliance['team_keys'];
      if (keys is! List) {
        return const <int>[];
      }
      // TBA team keys look like "frc1234".
      return keys
          .whereType<String>()
          .map((k) => int.tryParse(k.replaceFirst('frc', '')) ?? 0)
          .where((t) => t > 0)
          .toList(growable: false);
    }

    final alliances = (json['alliances'] as Map?) ?? const {};
    return TbaScheduleMatch(
      key: (json['key'] as String?) ?? '',
      compLevel: (json['comp_level'] as String?) ?? 'qm',
      matchNumber: (json['match_number'] as num?)?.toInt() ?? 0,
      redTeams: extractTeams(alliances['red']),
      blueTeams: extractTeams(alliances['blue']),
    );
  }

  final String key;
  final String compLevel;
  final int matchNumber;
  final List<int> redTeams;
  final List<int> blueTeams;
}

class TbaApiStatus {
  TbaApiStatus({required this.currentSeason, required this.maxSeason});

  factory TbaApiStatus.fromJson(Map<String, dynamic> json) {
    return TbaApiStatus(
      currentSeason: (json['current_season'] as num).toInt(),
      maxSeason: (json['max_season'] as num).toInt(),
    );
  }

  final int currentSeason;
  final int maxSeason;
}

/// A video associated with a TBA match (usually YouTube).
class TbaMatchVideo {
  const TbaMatchVideo({required this.type, required this.key});

  factory TbaMatchVideo.fromJson(Map<String, dynamic> json) {
    return TbaMatchVideo(
      type: (json['type'] as String?) ?? '',
      key: (json['key'] as String?) ?? '',
    );
  }

  /// Video platform type, e.g. `"youtube"`.
  final String type;

  /// Platform-specific video key (YouTube video ID for YouTube videos).
  final String key;

  bool get isYoutube => type == 'youtube';

  /// Full YouTube watch URL, or null if this is not a YouTube video.
  String? get youtubeUrl {
    if (!isYoutube || key.isEmpty) return null;
    return 'https://www.youtube.com/watch?v=$key';
  }
}

/// Minimal TBA match response for video lookup.
class TbaMatch {
  const TbaMatch({required this.key, required this.videos});

  factory TbaMatch.fromJson(Map<String, dynamic> json) {
    final rawVideos = (json['videos'] as List<dynamic>?) ?? <dynamic>[];
    return TbaMatch(
      key: (json['key'] as String?) ?? '',
      videos: rawVideos
          .whereType<Map<String, dynamic>>()
          .map(TbaMatchVideo.fromJson)
          .toList(growable: false),
    );
  }

  /// TBA match key, e.g. `2025flor_qm14`.
  final String key;

  /// Videos attached to this match.
  final List<TbaMatchVideo> videos;

  /// The first YouTube video, if any.
  TbaMatchVideo? get youtubeVideo {
    for (final v in videos) {
      if (v.isYoutube) return v;
    }
    return null;
  }
}
