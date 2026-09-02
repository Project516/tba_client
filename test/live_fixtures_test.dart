import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tba_client/tba_client.dart';
import 'package:test/test.dart';

/// Decodes a captured response body from `test/fixtures/`.
///
/// These are real `thebluealliance.com/api/v3` bodies, saved on 2026-09-02.
/// The hand-written maps in `tba_client_test.dart` are readable, but they are
/// also the author's belief about the API, and a model can satisfy every one
/// of them while failing on the real thing. Assert against a captured body
/// and a shape change fails a test instead of reaching a consumer.
///
/// List and map bodies are trimmed to the first few entries so a fixture
/// stays reviewable; each entry that remains is byte-for-byte as TBA sent it,
/// and `sort_order_info` / `extra_stats_info` are kept whole because their
/// length is what positional decoding depends on. Refresh one with:
/// `curl -H "X-TBA-Auth-Key: $KEY" https://www.thebluealliance.com/api/v3/<path>`
///
/// One case is deliberately not here: an unplayed match, where TBA sends
/// `score: -1` and an empty `winning_alliance`. No live event had one on the
/// capture date, so that stays covered by a hand-written body in
/// `tba_client_test.dart`.
String _fixture(String name) =>
    File('test/fixtures/$name.json').readAsStringSync();

Object _json(String name) => jsonDecode(_fixture(name));

/// A client that answers every request with [name]'s captured body.
TbaClient _clientServing(String name) => TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: MockClient(
        (_) async => http.Response(
          _fixture(name),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      ),
    );

void main() {
  group('captured live responses', () {
    test('TbaApiStatus decodes a real /status body', () async {
      final status = await _clientServing('status').getStatus();

      expect(status.currentSeason, 2026);
      expect(status.maxSeason, 2026);
    });

    test('TbaTeam decodes a real /team body', () async {
      final team = await _clientServing('team').getTeam(254);

      expect(team, isNotNull);
      expect(team!.key, 'frc254');
      expect(team.teamNumber, 254);
      expect(team.nickname, 'The Cheesy Poofs');
      expect(team.displayLocation, 'San Jose, California, USA');
      // TBA's `name` is the sponsor list, not the nickname, and it is long.
      expect(team.name, contains('NASA Ames'));
    });

    test('TbaTeam decodes a real /teams/simple row', () async {
      final teams =
          await _clientServing('event_teams_simple').getEventTeams('2025cabe');

      expect(teams, hasLength(2));
      expect(teams.first.key, startsWith('frc'));
      expect(teams.first.teamNumber, greaterThan(0));
      expect(teams.first.nickname, isNotEmpty);
    });

    test('TbaEvent decodes a real /event body, week made one-based', () async {
      final event = await _clientServing('event').getEvent('2025cabe');

      expect(event, isNotNull);
      expect(event!.key, '2025cabe');
      expect(event.name, 'East Bay Regional');
      expect(event.year, 2025);
      expect(event.stateProv, 'CA');
      expect(event.country, 'USA');
      expect(event.startDate, '2025-04-03');
      expect(event.endDate, '2025-04-06');
      // TBA sends week 5 zero-based; humans and Statbotics both call it 6.
      expect((_json('event') as Map)['week'], 5);
      expect(event.week, 6);
    });

    test('TbaEvent decodes a real /events/{year} row', () async {
      final events = await _clientServing('events_year').getEventsForYear(2025);

      expect(events, hasLength(2));
      expect(events.first.key, startsWith('2025'));
      expect(events.first.year, 2025);
      expect(events.first.name, isNotEmpty);
    });

    test('TbaScheduleMatch decodes a real /matches/simple row', () async {
      final matches = await _clientServing('event_matches_simple')
          .getEventMatches('2025cabe');

      final finals = matches.firstWhere((m) => m.compLevel == 'f');
      expect(finals.key, '2025cabe_f1m1');
      expect(finals.redTeams, <int>[254, 2204, 4270]);
      expect(finals.blueTeams, <int>[8033, 972, 8793]);
      expect(finals.redScore, 239);
      expect(finals.blueScore, 220);
      expect(finals.winningAlliance, 'red');
      expect(finals.isPlayed, isTrue);
      expect(finals.isTie, isFalse);
      expect(finals.scheduledTime, isNotNull);
      expect(finals.predictedTime, isNotNull);
      expect(finals.actualTime, isNotNull);
      // /matches/simple carries no score_breakdown; the detailed one does.
      expect(finals.scoreBreakdown, isEmpty);
    });

    test('TbaScheduleMatch reads score_breakdown from /matches', () async {
      final matches = await _clientServing('event_matches_detailed')
          .getEventMatchesDetailed('2025cabe');

      final red = matches.single.scoreBreakdown['red'];
      expect(matches.single.scoreBreakdown.keys, containsAll(['red', 'blue']));
      expect(red, isNotNull);
      // Season-specific keys, which is why the map stays open rather than
      // becoming named fields.
      expect(red!.keys, contains('autoCoralCount'));
      expect(red.keys, contains('teleopPoints'));
      expect(red['totalPoints'], 239);
    });

    test('TbaMatch decodes a real /match body with its videos', () async {
      final match = await _clientServing('match').getMatch('2025cabe_f1m1');

      expect(match, isNotNull);
      expect(match!.key, '2025cabe_f1m1');
      expect(match.videos, hasLength(1));
      expect(match.videos.single.type, 'youtube');
      expect(match.videos.single.key, 'rC6xTPwthSg');
    });

    test('fetchTeamAvatar finds the avatar among other media', () async {
      // The media list mixes types, and the bytes live two levels down at
      // details.base64Image. The fixture deliberately puts a non-avatar
      // entry first, so a scan that stopped at the first item would fail.
      final media = _json('team_media') as List;
      expect(media.first['type'], isNot('avatar'));
      expect(media.last['type'], 'avatar');
      expect((media.last['details'] as Map).keys, ['base64Image']);

      final bytes =
          await _clientServing('team_media').fetchTeamAvatar(254, 2025);

      expect(bytes, isNotNull);
      expect(bytes!.length, 1443);
      // A 40x40 PNG, so it starts with the PNG magic number.
      expect(bytes.take(4), <int>[0x89, 0x50, 0x4E, 0x47]);
    });

    test('fetchTeamAvatar returns null when no entry is an avatar', () async {
      // Same real media list with the avatar removed, which is the common
      // case: most teams have no avatar for a given year.
      final withoutAvatar = (_json('team_media') as List)
          .where((m) => (m as Map)['type'] != 'avatar')
          .toList();
      final client = TbaClient(
        config: InMemoryTbaConfig('test-key'),
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(withoutAvatar), 200),
        ),
      );

      expect(await client.fetchTeamAvatar(254, 2025), isNull);
    });

    test('TbaEventOprs decodes a real /oprs body', () async {
      final oprs = await _clientServing('event_oprs').getEventOprs('2025cabe');

      expect(oprs, isNotNull);
      expect(oprs!.isEmpty, isFalse);
      expect(oprs.oprs, isNotEmpty);
      expect(oprs.dprs, isNotEmpty);
      expect(oprs.ccwms, isNotEmpty);
      // Keyed by TBA team key, not team number.
      expect(oprs.oprs.keys.first, startsWith('frc'));
      expect(oprs.oprs.length, oprs.dprs.length);
    });

    test('TbaEventCoprs is stat major, not team major', () async {
      final coprs =
          await _clientServing('event_coprs').getEventCoprs('2025cabe');

      expect(coprs, isNotNull);
      expect(coprs!.isEmpty, isFalse);
      // The outer keys are stat names. Reading them as team keys made every
      // lookup miss, which is the bug this asserts against.
      expect(coprs.statNames, contains('L1 Coral Count'));
      expect(coprs.statNames.every((s) => !s.startsWith('frc')), isTrue);
      final team = coprs.stats.values.first.keys.first;
      expect(team, startsWith('frc'));
      expect(coprs.forTeam(team), isNotEmpty);
      // Plain OPR is not among the component OPRs; it comes from /oprs.
      expect(coprs.statNames, isNot(contains('OPR')));
    });

    test('TbaEventRankings decodes a real /rankings body', () async {
      final rankings =
          await _clientServing('event_rankings').getEventRankings('2025cabe');

      expect(rankings, isNotNull);
      expect(rankings!.isEmpty, isFalse);
      final first = rankings.rankings.first;
      expect(first.teamKey, 'frc254');
      expect(first.rank, 1);
      expect(first.wins, 9);
      expect(first.losses, 0);
      expect(first.ties, 0);
      expect(first.matchesPlayed, 9);
      expect(first.dq, 0);
      expect(rankings.sortOrderNames.first, 'Ranking Score');
      expect(rankings.sortOrdersFor(first)['Ranking Score'], 5.89);
    });

    test('rankings drop a sort order TBA gives no name for', () async {
      // TBA sends six sort_orders and five sort_order_info entries on this
      // event, so the last value is unlabelled. Dropping it is deliberate:
      // a column nobody can label is not worth showing.
      final raw = _json('event_rankings') as Map;
      expect((raw['sort_order_info'] as List), hasLength(5));
      expect(
        ((raw['rankings'] as List).first as Map)['sort_orders'] as List,
        hasLength(6),
      );

      final rankings =
          await _clientServing('event_rankings').getEventRankings('2025cabe');
      expect(rankings!.sortOrderNames, hasLength(5));
      expect(rankings.sortOrdersFor(rankings.rankings.first), hasLength(5));
    });

    test('TbaEventAlliances keeps pick order', () async {
      final alliances =
          await _clientServing('event_alliances').getEventAlliances('2025cabe');

      expect(alliances, isNotNull);
      expect(alliances!.alliances, hasLength(8));
      final first = alliances.alliances.first;
      expect(first.name, 'Alliance 1');
      // Captain first, then picks in the order they were made. Never sorted.
      expect(first.picks, <String>['frc254', 'frc4270', 'frc2204']);
      expect(first.captain, 'frc254');
      expect(first.status, 'f');
      expect(first.record, '5-0-0');
    });

    test('TbaEventAwards decodes a real /awards body', () async {
      final awards =
          await _clientServing('event_awards').getEventAwards('2025cabe');

      expect(awards, isNotNull);
      expect(awards!.awards, hasLength(3));
      final impact = awards.awards.first;
      expect(impact.name, 'Regional FIRST Impact Award');
      expect(impact.awardType, 0);
      expect(impact.recipients, hasLength(1));
      expect(impact.recipients.single.teamKey, 'frc5985');
      // A team award has no named awardee.
      expect(impact.recipients.single.awardee, isNull);
    });

    test('predictions merge the qual and playoff sections', () async {
      // TBA nests match_predictions under a level key. Reading only one
      // section would silently lose half the event.
      final raw =
          (_json('event_predictions') as Map)['match_predictions'] as Map;
      expect(raw.keys, containsAll(['qual', 'playoff']));

      final predictions = await _clientServing('event_predictions')
          .getEventPredictions('2025cabe');

      expect(predictions.keys, containsAll(['2025cabe_qm1', '2025cabe_f1m1']));
      final qm1 = predictions['2025cabe_qm1']!;
      expect(qm1.matchKey, '2025cabe_qm1');
      expect(qm1.redScore, greaterThan(0));
      expect(qm1.blueScore, greaterThan(0));
      expect(qm1.probability, inInclusiveRange(0, 1));
      expect(qm1.winningAlliance, anyOf('red', 'blue'));
    });
  });
}
