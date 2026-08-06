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
    this.redScore,
    this.blueScore,
    this.winningAlliance,
    this.scheduledTime,
    this.predictedTime,
    this.actualTime,
    this.videos = const <TbaMatchVideo>[],
    this.scoreBreakdown = const <String, Map<String, dynamic>>{},
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

    // TBA sends -1, not null, for a match that has not been played. Passing
    // that through would render as a real score of minus one, so it becomes
    // null here and callers distinguish "no result yet" from "scored zero".
    int? extractScore(Object? alliance) {
      if (alliance is! Map) return null;
      final score = alliance['score'];
      if (score is! num) return null;
      final value = score.toInt();
      return value < 0 ? null : value;
    }

    DateTime? epochSeconds(Object? value) {
      if (value is! num) return null;
      final seconds = value.toInt();
      if (seconds <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      );
    }

    final alliances = (json['alliances'] as Map?) ?? const {};
    final rawWinner = json['winning_alliance'];
    final breakdown = <String, Map<String, dynamic>>{};
    final rawBreakdown = json['score_breakdown'];
    if (rawBreakdown is Map) {
      rawBreakdown.forEach((alliance, values) {
        if (values is Map) {
          breakdown[alliance.toString()] = Map<String, dynamic>.unmodifiable(
            values.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      });
    }

    return TbaScheduleMatch(
      key: (json['key'] as String?) ?? '',
      compLevel: (json['comp_level'] as String?) ?? 'qm',
      matchNumber: (json['match_number'] as num?)?.toInt() ?? 0,
      redTeams: extractTeams(alliances['red']),
      blueTeams: extractTeams(alliances['blue']),
      redScore: extractScore(alliances['red']),
      blueScore: extractScore(alliances['blue']),
      // Empty string means unplayed, and also means a tie, so it is not a
      // winner and must not become one.
      winningAlliance:
          rawWinner is String && rawWinner.isNotEmpty ? rawWinner : null,
      scheduledTime: epochSeconds(json['time']),
      predictedTime: epochSeconds(json['predicted_time']),
      actualTime: epochSeconds(json['actual_time']),
      videos: TbaMatchVideo.listFromJson(json['videos']),
      scoreBreakdown: Map<String, Map<String, dynamic>>.unmodifiable(breakdown),
    );
  }

  final String key;
  final String compLevel;
  final int matchNumber;
  final List<int> redTeams;
  final List<int> blueTeams;

  /// Final scores, or null when the match has not been played. Null rather than
  /// zero or -1 on purpose: an unplayed match and a scoreless one are different.
  final int? redScore;
  final int? blueScore;

  /// `red` or `blue`, or null for unplayed **and for a tie**. TBA sends an empty
  /// string for both, so this cannot distinguish them; [isPlayed] can.
  final String? winningAlliance;

  /// When the match was originally scheduled, in UTC.
  final DateTime? scheduledTime;

  /// TBA's current estimate of when the match will run, in UTC. This is the one
  /// worth showing during an event, since a schedule drifts.
  final DateTime? predictedTime;

  /// When the match actually ran, in UTC. Null until it does.
  final DateTime? actualTime;

  /// Match videos, if any have been posted.
  final List<TbaMatchVideo> videos;

  /// Game-specific per-alliance breakdown, keyed `red`/`blue` then by the
  /// season's own field names, which is where ranking points live. Open maps
  /// because the keys change every year; empty for unplayed matches and for
  /// events that do not publish one.
  final Map<String, Map<String, dynamic>> scoreBreakdown;

  /// Whether the match has a result. Both scores present is the reliable
  /// signal; `winning_alliance` is empty for a tie as well as for unplayed.
  bool get isPlayed => redScore != null && blueScore != null;

  /// True when the match was played and neither alliance won.
  bool get isTie => isPlayed && (winningAlliance == null);
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

  /// Parses a `videos` array from either the match or the schedule payload,
  /// tolerating a missing or wrong-typed value. Shared so the two callers
  /// cannot drift.
  static List<TbaMatchVideo> listFromJson(Object? raw) {
    if (raw is! List) return const <TbaMatchVideo>[];
    return List<TbaMatchVideo>.unmodifiable(
      raw
          .whereType<Map>()
          .map((v) => TbaMatchVideo.fromJson(Map<String, dynamic>.from(v))),
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
    return TbaMatch(
      key: (json['key'] as String?) ?? '',
      videos: TbaMatchVideo.listFromJson(json['videos']),
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

/// Component OPR (COPRS) data for an event, from
/// `GET /event/{event_key}/coprs`.
///
/// TBA returns a flat JSON object keyed by team key, where each value is a
/// map of stat name to number. The stat names are not fixed across game
/// years (the 2025 breakdown is 20+ columns), so this model carries an open
/// `Map<String, Map<String, num>>` rather than named fields -- unlike
/// [TbaEvent] / [TbaScheduleMatch], which have a stable shape.
///
/// Common stats include `"OPR"` (Offensive Power Rating), `"DPR"`
/// (Defensive Power Rating), `"ccwm"` (Calculating Contribution to Winning
/// Margin), and `"Foul Points"`, but the set varies per game year.
class TbaEventCoprs {
  TbaEventCoprs({required this.eventKey, required this.stats});

  /// Parses the endpoint's own shape, which is **stat major**: the outer keys
  /// are stat names and the inner keys are team keys. The first version of
  /// this read the outer keys as team keys, which made every lookup miss
  /// (issue #9).
  factory TbaEventCoprs.fromJson(
    String eventKey,
    Map<String, dynamic> json,
  ) {
    final stats = <String, Map<String, num>>{};
    json.forEach((statName, value) {
      if (value is Map) {
        final byTeam = <String, num>{};
        value.forEach((teamKey, statValue) {
          if (statValue is num) {
            byTeam[teamKey.toString()] = statValue;
          }
        });
        stats[statName.toString()] = byTeam;
      }
    });
    return TbaEventCoprs(eventKey: eventKey, stats: stats);
  }

  /// The event key this COPRS breakdown belongs to, e.g. `2026txhou`.
  final String eventKey;

  /// Stat name to team-keyed values, mirroring the endpoint: for example
  /// `{"foulPoints": {"frc254": 4.5}}`. Stat names vary by game year and mix
  /// human-readable (`Total Coral Points`) with raw camelCase
  /// (`teleopCoralPoints`), so they cannot be enumerated ahead of time.
  /// Entries with a non-numeric value are skipped.
  ///
  /// Note this endpoint carries *component* OPRs only. Plain OPR, DPR and
  /// CCWM are not among these stat names; they come from [TbaEventOprs].
  final Map<String, Map<String, num>> stats;

  /// Whether the breakdown holds no stats.
  bool get isEmpty => stats.isEmpty;

  /// Every stat name present, in the order the endpoint returned them. This is
  /// what a column picker offers, since the set changes every season.
  Iterable<String> get statNames => stats.keys;

  /// The team-keyed values for [statName], or null when absent.
  Map<String, num>? operator [](String statName) => stats[statName];

  /// Every stat this event reports for [teamKey], as stat name to value.
  /// Derived rather than stored, so it cannot fall out of step with [stats].
  /// Empty when the team did not attend.
  Map<String, num> forTeam(String teamKey) {
    final result = <String, num>{};
    stats.forEach((statName, byTeam) {
      final value = byTeam[teamKey];
      if (value != null) {
        result[statName] = value;
      }
    });
    return result;
  }
}

/// `GET /event/{eventKey}/oprs`: plain OPR, DPR and CCWM for an event.
///
/// Separate from [TbaEventCoprs] because TBA serves them separately, and
/// because the COPRs endpoint does not include OPR at all -- a consumer
/// wanting an OPR column has to come here for it (issue #9).
class TbaEventOprs {
  TbaEventOprs({
    required this.eventKey,
    required this.oprs,
    required this.dprs,
    required this.ccwms,
  });

  factory TbaEventOprs.fromJson(String eventKey, Map<String, dynamic> json) {
    Map<String, num> section(String name) {
      final raw = json[name];
      if (raw is! Map) return const <String, num>{};
      final result = <String, num>{};
      raw.forEach((teamKey, value) {
        if (value is num) {
          result[teamKey.toString()] = value;
        }
      });
      return result;
    }

    return TbaEventOprs(
      eventKey: eventKey,
      oprs: section('oprs'),
      dprs: section('dprs'),
      ccwms: section('ccwms'),
    );
  }

  /// The event key this breakdown belongs to, e.g. `2026txhou`.
  final String eventKey;

  /// Offensive power rating per team, keyed by team key (e.g. `frc254`).
  final Map<String, num> oprs;

  /// Defensive power rating per team.
  final Map<String, num> dprs;

  /// Calculated contribution to win margin per team.
  final Map<String, num> ccwms;

  /// Whether every section came back empty.
  bool get isEmpty => oprs.isEmpty && dprs.isEmpty && ccwms.isEmpty;
}

/// `GET /event/{eventKey}/rankings`: the qualification ranking table (#11).
class TbaEventRankings {
  const TbaEventRankings({
    required this.eventKey,
    required this.rankings,
    required this.sortOrderNames,
  });

  factory TbaEventRankings.fromJson(
      String eventKey, Map<String, dynamic> json) {
    final rawRankings = json['rankings'];
    final rankings = <TbaTeamRanking>[
      if (rawRankings is List)
        for (final row in rawRankings.whereType<Map>())
          TbaTeamRanking.fromJson(Map<String, dynamic>.from(row)),
    ];
    final rawInfo = json['sort_order_info'];
    final names = <String>[
      if (rawInfo is List)
        for (final info in rawInfo.whereType<Map>())
          (info['name'] ?? '').toString(),
    ];
    return TbaEventRankings(
      eventKey: eventKey,
      rankings: List<TbaTeamRanking>.unmodifiable(rankings),
      sortOrderNames: List<String>.unmodifiable(names),
    );
  }

  final String eventKey;

  /// One row per team, in the order TBA returned them (rank order).
  final List<TbaTeamRanking> rankings;

  /// What each entry in [TbaTeamRanking.sortOrders] means, positionally. The
  /// names are game specific and change every season, so they are read from the
  /// payload rather than hardcoded, the same way COPRs stat names are.
  final List<String> sortOrderNames;

  bool get isEmpty => rankings.isEmpty;

  /// [TbaTeamRanking.sortOrders] paired with [sortOrderNames], which is what a
  /// table wants. Extra values with no matching name are dropped, since a column
  /// nobody can label is not worth showing.
  Map<String, num> sortOrdersFor(TbaTeamRanking ranking) {
    final result = <String, num>{};
    for (var i = 0; i < sortOrderNames.length; i++) {
      if (i >= ranking.sortOrders.length) break;
      result[sortOrderNames[i]] = ranking.sortOrders[i];
    }
    return result;
  }
}

/// One team's row in the ranking table.
class TbaTeamRanking {
  const TbaTeamRanking({
    required this.rank,
    required this.teamKey,
    required this.wins,
    required this.losses,
    required this.ties,
    required this.matchesPlayed,
    required this.dq,
    required this.qualAverage,
    required this.sortOrders,
  });

  factory TbaTeamRanking.fromJson(Map<String, dynamic> json) {
    final record = json['record'];
    int fromRecord(String field) {
      if (record is! Map) return 0;
      final value = record[field];
      return value is num ? value.toInt() : 0;
    }

    final rawSort = json['sort_orders'];
    return TbaTeamRanking(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      teamKey: (json['team_key'] as String?) ?? '',
      wins: fromRecord('wins'),
      losses: fromRecord('losses'),
      ties: fromRecord('ties'),
      matchesPlayed: (json['matches_played'] as num?)?.toInt() ?? 0,
      dq: (json['dq'] as num?)?.toInt() ?? 0,
      qualAverage: (json['qual_average'] as num?)?.toDouble(),
      sortOrders: List<num>.unmodifiable(
        rawSort is List ? rawSort.whereType<num>() : const <num>[],
      ),
    );
  }

  final int rank;
  final String teamKey;
  final int wins;
  final int losses;
  final int ties;
  final int matchesPlayed;
  final int dq;

  /// Average qualification score. Null for seasons that do not report one.
  final double? qualAverage;

  /// The season's ranking sort values, positional. Pair them with
  /// [TbaEventRankings.sortOrderNames] via
  /// [TbaEventRankings.sortOrdersFor] rather than indexing blind.
  final List<num> sortOrders;

  String get record => '$wins-$losses-$ties';
}

/// `GET /event/{eventKey}/alliances`: playoff alliances as picked (#11).
class TbaEventAlliances {
  const TbaEventAlliances({required this.eventKey, required this.alliances});

  factory TbaEventAlliances.fromJson(String eventKey, List<dynamic> json) {
    return TbaEventAlliances(
      eventKey: eventKey,
      alliances: List<TbaAlliance>.unmodifiable(
        json
            .whereType<Map>()
            .map((a) => TbaAlliance.fromJson(Map<String, dynamic>.from(a))),
      ),
    );
  }

  final String eventKey;
  final List<TbaAlliance> alliances;

  bool get isEmpty => alliances.isEmpty;
}

/// One playoff alliance.
class TbaAlliance {
  const TbaAlliance({
    required this.name,
    required this.picks,
    required this.status,
    required this.record,
  });

  factory TbaAlliance.fromJson(Map<String, dynamic> json) {
    final rawPicks = json['picks'];
    final status = json['status'];
    String statusLevel = '';
    String record = '';
    if (status is Map) {
      statusLevel = (status['level'] ?? '').toString();
      final rec = status['record'];
      if (rec is Map) {
        final w = (rec['wins'] as num?)?.toInt() ?? 0;
        final l = (rec['losses'] as num?)?.toInt() ?? 0;
        final t = (rec['ties'] as num?)?.toInt() ?? 0;
        record = '$w-$l-$t';
      }
    }
    return TbaAlliance(
      name: (json['name'] as String?) ?? '',
      // Pick order is the interesting part -- who picked whom -- so it is
      // preserved exactly as returned and never sorted.
      picks: List<String>.unmodifiable(
        rawPicks is List ? rawPicks.whereType<String>() : const <String>[],
      ),
      status: statusLevel,
      record: record,
    );
  }

  final String name;

  /// Team keys in pick order: captain first, then first pick, and so on.
  final List<String> picks;

  /// How far the alliance got, e.g. `f`, `sf`, or empty when not reported.
  final String status;

  /// Playoff record as `wins-losses-ties`, or empty when not reported.
  final String record;

  String? get captain => picks.isEmpty ? null : picks.first;
}

/// `GET /event/{eventKey}/awards`: awards presented at an event (#11).
class TbaEventAwards {
  const TbaEventAwards({required this.eventKey, required this.awards});

  factory TbaEventAwards.fromJson(String eventKey, List<dynamic> json) {
    return TbaEventAwards(
      eventKey: eventKey,
      awards: List<TbaAward>.unmodifiable(
        json
            .whereType<Map>()
            .map((a) => TbaAward.fromJson(Map<String, dynamic>.from(a))),
      ),
    );
  }

  final String eventKey;
  final List<TbaAward> awards;

  bool get isEmpty => awards.isEmpty;

  /// Every award [teamKey] received at this event.
  List<TbaAward> forTeam(String teamKey) => List<TbaAward>.unmodifiable(
        awards.where((a) => a.recipients.any((r) => r.teamKey == teamKey)),
      );
}

/// One award and who received it.
class TbaAward {
  const TbaAward({
    required this.name,
    required this.awardType,
    required this.recipients,
  });

  factory TbaAward.fromJson(Map<String, dynamic> json) {
    final rawRecipients = json['recipient_list'];
    return TbaAward(
      name: (json['name'] as String?) ?? '',
      awardType: (json['award_type'] as num?)?.toInt() ?? 0,
      recipients: List<TbaAwardRecipient>.unmodifiable(
        rawRecipients is List
            ? rawRecipients.whereType<Map>().map(
                  (r) =>
                      TbaAwardRecipient.fromJson(Map<String, dynamic>.from(r)),
                )
            : const <TbaAwardRecipient>[],
      ),
    );
  }

  final String name;
  final int awardType;
  final List<TbaAwardRecipient> recipients;
}

/// An award recipient: a team, a person, or both.
class TbaAwardRecipient {
  const TbaAwardRecipient({required this.teamKey, required this.awardee});

  factory TbaAwardRecipient.fromJson(Map<String, dynamic> json) {
    final team = json['team_key'];
    final awardee = json['awardee'];
    return TbaAwardRecipient(
      teamKey: team is String && team.isNotEmpty ? team : null,
      // Set for individual awards (Dean's List, Woodie Flowers), null for team
      // awards.
      awardee: awardee is String && awardee.isNotEmpty ? awardee : null,
    );
  }

  final String? teamKey;
  final String? awardee;
}

/// TBA's own predicted outcome for one match (`/event/{key}/predictions`).
///
/// The payload also carries per-game component means and variances, which are
/// renamed every season, so only the season-independent parts are modelled:
/// the two predicted scores, the alliance TBA expects to win, and how confident
/// it is. [probability] is TBA's confidence in [winningAlliance], not the red
/// alliance's chance, so it is always at least 0.5 on a well-formed payload.
class TbaMatchPrediction {
  const TbaMatchPrediction({
    required this.matchKey,
    required this.redScore,
    required this.blueScore,
    required this.winningAlliance,
    required this.probability,
  });

  factory TbaMatchPrediction.fromJson(String matchKey, Map<String, dynamic> j) {
    double score(Object? alliance) {
      if (alliance is! Map) return 0;
      final value = alliance['score'];
      return value is num ? value.toDouble() : 0;
    }

    final winner = j['winning_alliance'];
    final prob = j['prob'];
    return TbaMatchPrediction(
      matchKey: matchKey,
      redScore: score(j['red']),
      blueScore: score(j['blue']),
      winningAlliance: winner is String ? winner : '',
      probability: prob is num ? prob.toDouble() : 0,
    );
  }

  final String matchKey;
  final double redScore;
  final double blueScore;

  /// `red`, `blue`, or empty when the payload does not say.
  final String winningAlliance;

  /// TBA's confidence in [winningAlliance], 0 to 1.
  final double probability;
}
