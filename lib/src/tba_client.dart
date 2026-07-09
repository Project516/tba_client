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
  Future<List<TbaScheduleMatch>> getEventMatches(String eventKey) async {
    final body = await _get('/event/$eventKey/matches/simple');
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
