import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'tba_config.dart';
import 'tba_models.dart';

/// Thin client for The Blue Alliance API v3.
///
/// Adds the `X-TBA-Auth-Key` header on every request (TBA strongly recommends
/// the header form over the query-string form because URL-embedded keys defeat
/// CDN caching). Caching via ETag / If-None-Match is a follow-up and is not
/// implemented here.
class TbaClient {
  TbaClient({required TbaConfig config, http.Client? httpClient})
      : _config = config,
        _httpClient = httpClient ?? http.Client();

  static const String baseUrl = 'https://www.thebluealliance.com/api/v3';

  final TbaConfig _config;
  final http.Client _httpClient;

  /// `GET /status` — returns the API status payload. Useful as a connectivity
  /// and auth-key smoke test.
  Future<TbaApiStatus> getStatus() async {
    final body = await _getStatusBody();
    return TbaApiStatus.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// `GET /team/frc{teamNumber}` — returns the team, or null on 404.
  Future<TbaTeam?> getTeam(int teamNumber) async {
    final body = await _get('/team/frc$teamNumber');
    if (body == null) {
      return null;
    }
    return TbaTeam.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// `GET /event/{eventKey}/teams/simple` — list of teams attending the event.
  Future<List<TbaTeam>> getEventTeams(String eventKey) async {
    final body = await _get('/event/$eventKey/teams/simple');
    if (body == null) {
      return const <TbaTeam>[];
    }
    final list = jsonDecode(body) as List<dynamic>;
    return list
        .map((json) => TbaTeam.fromJson(Map<String, dynamic>.from(json as Map)))
        .toList(growable: false);
  }

  /// `GET /team/frc{teamNumber}/media/{year}` — returns the team's FIRST
  /// avatar (a 40x40 PNG that teams upload to FIRST) for [year] as decoded
  /// bytes, or null when the team has no avatar that year or the request 404s.
  /// Throws [TbaApiKeyMissingException] when no key is configured, so callers
  /// can tell "no key" apart from "no avatar".
  Future<Uint8List?> fetchTeamAvatar(int teamNumber, int year) async {
    final body = await _get('/team/frc$teamNumber/media/$year');
    if (body == null) {
      return null;
    }
    final media = jsonDecode(body) as List<dynamic>;
    for (final item in media) {
      if (item is Map && item['type'] == 'avatar') {
        final details = item['details'];
        final encoded = details is Map ? details['base64Image'] : null;
        if (encoded is String && encoded.isNotEmpty) {
          try {
            return base64Decode(encoded);
          } on FormatException {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// `GET /event/{eventKey}` — returns the event, or null on 404. Used as
  /// the event-info fallback when Statbotics is down (#512).
  Future<TbaEvent?> getEvent(String eventKey) async {
    final body = await _get('/event/$eventKey');
    if (body == null) {
      return null;
    }
    return TbaEvent.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// `GET /events/{year}` — all events for [year]. Used as the event-list
  /// fallback when Statbotics is down (#512).
  Future<List<TbaEvent>> getEventsForYear(int year) async {
    final body = await _get('/events/$year');
    if (body == null) {
      return const <TbaEvent>[];
    }
    final list = jsonDecode(body) as List<dynamic>;
    return list
        .map(
          (json) => TbaEvent.fromJson(Map<String, dynamic>.from(json as Map)),
        )
        .toList(growable: false);
  }

  /// `GET /event/{eventKey}/matches/simple` — the event's match schedule.
  /// Used as the schedule fallback when Statbotics is down (#512).
  ///
  /// The `simple` payload carries the teams, the scores, the winner and the
  /// three time fields, but **not** `videos` or `score_breakdown`. Use
  /// [getEventMatchesDetailed] for those (#15).
  Future<List<TbaScheduleMatch>> getEventMatches(String eventKey) =>
      _matches('/event/$eventKey/matches/simple');

  /// `GET /event/{eventKey}/matches` — the full match payload, which adds
  /// `videos` and `score_breakdown` to what [getEventMatches] returns.
  ///
  /// A separate call rather than switching [getEventMatches] over, because a
  /// score breakdown is large and the schedule is fetched on every event change
  /// and again on every pull-to-refresh. A consumer that only wants the schedule
  /// and the scores should not pay for breakdowns it will not read, which matters
  /// on the venue wifi these consumers run on (#15).
  Future<List<TbaScheduleMatch>> getEventMatchesDetailed(String eventKey) =>
      _matches('/event/$eventKey/matches');

  Future<List<TbaScheduleMatch>> _matches(String path) async {
    final body = await _get(path);
    if (body == null) {
      return const <TbaScheduleMatch>[];
    }
    final list = jsonDecode(body) as List<dynamic>;
    return list
        .map(
          (json) =>
              TbaScheduleMatch.fromJson(Map<String, dynamic>.from(json as Map)),
        )
        .toList(growable: false);
  }

  /// `GET /event/{eventKey}/coprs` — component OPR breakdown for the event,
  /// or null on 404.
  ///
  /// Stat major, matching the endpoint: stat name -> team key -> value. The
  /// stat names are game specific and change every season, so the model keeps
  /// an open map rather than named fields. Component OPRs only: plain OPR,
  /// DPR and CCWM are not here, see [getEventOprs] (#6, #9).
  Future<TbaEventCoprs?> getEventCoprs(String eventKey) async {
    final body = await _get('/event/$eventKey/coprs');
    if (body == null) {
      return null;
    }
    final decoded = jsonDecode(body);
    if (decoded == null) {
      return null;
    }
    return TbaEventCoprs.fromJson(
      eventKey,
      decoded as Map<String, dynamic>,
    );
  }

  /// `GET /event/{eventKey}/oprs` — plain OPR, DPR and CCWM per team, or null
  /// on 404. A separate call from [getEventCoprs] because TBA serves them
  /// separately and the COPRs payload has no OPR in it (#9).
  Future<TbaEventOprs?> getEventOprs(String eventKey) async {
    final body = await _get('/event/$eventKey/oprs');
    if (body == null) {
      return null;
    }
    final decoded = jsonDecode(body);
    if (decoded == null) {
      return null;
    }
    return TbaEventOprs.fromJson(
      eventKey,
      decoded as Map<String, dynamic>,
    );
  }

  /// `GET /event/{eventKey}/rankings` — the qualification ranking table, or
  /// null on 404 and for events that publish none (#11).
  Future<TbaEventRankings?> getEventRankings(String eventKey) async {
    final body = await _get('/event/$eventKey/rankings');
    if (body == null) {
      return null;
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      // TBA answers `null` for an event with no rankings yet, which is a normal
      // pre-event state rather than an error.
      return null;
    }
    return TbaEventRankings.fromJson(eventKey, decoded);
  }

  /// `GET /event/{eventKey}/alliances` — playoff alliances in pick order, or
  /// null on 404 and before alliance selection has happened (#11).
  Future<TbaEventAlliances?> getEventAlliances(String eventKey) async {
    final body = await _get('/event/$eventKey/alliances');
    if (body == null) {
      return null;
    }
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      return null;
    }
    return TbaEventAlliances.fromJson(eventKey, decoded);
  }

  /// `GET /event/{eventKey}/awards` — awards presented at the event, or null on
  /// 404. An empty list is normal until the awards ceremony (#11).
  Future<TbaEventAwards?> getEventAwards(String eventKey) async {
    final body = await _get('/event/$eventKey/awards');
    if (body == null) {
      return null;
    }
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      return null;
    }
    return TbaEventAwards.fromJson(eventKey, decoded);
  }

  /// `GET /event/{eventKey}/predictions` — TBA's own predicted scores, keyed by
  /// match key.
  ///
  /// Empty rather than null when there is nothing to predict: TBA answers `{}`
  /// before it has enough data, which is the normal state early at an event and
  /// the permanent state at an offseason one. Qualification and playoff
  /// predictions arrive under separate keys and are merged here, since the
  /// match key already says which is which.
  Future<Map<String, TbaMatchPrediction>> getEventPredictions(
    String eventKey,
  ) async {
    final body = await _get('/event/$eventKey/predictions');
    if (body == null) {
      return const <String, TbaMatchPrediction>{};
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return const <String, TbaMatchPrediction>{};
    }
    final byLevel = decoded['match_predictions'];
    if (byLevel is! Map) {
      return const <String, TbaMatchPrediction>{};
    }
    final predictions = <String, TbaMatchPrediction>{};
    for (final level in byLevel.values) {
      if (level is! Map) continue;
      for (final entry in level.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || key.isEmpty || value is! Map) continue;
        predictions[key] = TbaMatchPrediction.fromJson(
          key,
          Map<String, dynamic>.from(value),
        );
      }
    }
    return Map<String, TbaMatchPrediction>.unmodifiable(predictions);
  }

  /// `GET /match/{matchKey}` — returns the match with its video list, or
  /// null on 404.
  Future<TbaMatch?> getMatch(String matchKey) async {
    final body = await _get('/match/$matchKey');
    if (body == null) {
      return null;
    }
    return TbaMatch.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  void close() {
    _httpClient.close();
  }

  Future<http.Response> _execute(String path) async {
    final apiKey = await _config.resolveApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw const TbaApiKeyMissingException();
    }
    return _httpClient.get(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{
        'X-TBA-Auth-Key': apiKey,
        'Accept': 'application/json',
      },
    );
  }

  Future<String> _getStatusBody() async {
    final response = await _execute('/status');
    if (response.statusCode == 404) {
      throw TbaApiException(
        404,
        response.body.isNotEmpty
            ? response.body
            : 'TBA /status returned 404. Check baseUrl and API key configuration.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TbaApiException(response.statusCode, response.body);
    }
    return response.body;
  }

  Future<String?> _get(String path) async {
    final response = await _execute(path);
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TbaApiException(response.statusCode, response.body);
    }
    return response.body;
  }
}

class TbaApiKeyMissingException implements Exception {
  const TbaApiKeyMissingException();

  @override
  String toString() =>
      'TBA API key is not configured. Ask an admin to set the team key in '
      'Settings, or paste a personal key there.';
}

class TbaApiException implements Exception {
  TbaApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'TBA API error $statusCode: $body';
}
