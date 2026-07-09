import 'dart:convert';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:tba_client/tba_client.dart';
import 'package:http/testing.dart';

void main() {
  test(
    'TbaClient.getTeam sends X-TBA-Auth-Key header and parses body',
    () async {
      final mockClient = MockClient((request) async {
        expect(request.headers['X-TBA-Auth-Key'], 'test-key');
        expect(
          request.url.toString(),
          'https://www.thebluealliance.com/api/v3/team/frc1234',
        );
        return http.Response(
          jsonEncode(<String, dynamic>{
            'key': 'frc1234',
            'team_number': 1234,
            'nickname': 'Example',
            'name': 'Example',
            'city': 'Houston',
            'state_prov': 'Texas',
            'country': 'USA',
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final client = TbaClient(
        config: InMemoryTbaConfig('test-key'),
        httpClient: mockClient,
      );

      final team = await client.getTeam(1234);
      expect(team, isNotNull);
      expect(team!.teamNumber, 1234);
      expect(team.nickname, 'Example');
      expect(team.displayLocation, 'Houston, Texas, USA');
    },
  );

  test('TbaClient.getTeam returns null on 404', () async {
    final mockClient = MockClient((_) async {
      return http.Response('', 404);
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    final team = await client.getTeam(99999);
    expect(team, isNull);
  });

  test('TbaClient.getTeam throws TbaApiException on non-2xx/non-404', () async {
    final mockClient = MockClient((_) async {
      return http.Response('server error', 500);
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    await expectLater(
      client.getTeam(1234),
      throwsA(
        isA<TbaApiException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.body, 'body', 'server error'),
      ),
    );
  });

  test(
    'TbaClient.getStatus throws TbaApiException with body content on 404 response',
    () async {
      final mockClient = MockClient((_) async {
        return http.Response('invalid auth key', 404);
      });

      final client = TbaClient(
        config: InMemoryTbaConfig('test-key'),
        httpClient: mockClient,
      );

      await expectLater(
        client.getStatus(),
        throwsA(
          isA<TbaApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.body, 'body', 'invalid auth key'),
        ),
      );
    },
  );

  test('TbaClient.getStatus parses successful 200 response', () async {
    final mockClient = MockClient((request) async {
      expect(request.headers['X-TBA-Auth-Key'], 'test-key');
      expect(
        request.url.toString(),
        'https://www.thebluealliance.com/api/v3/status',
      );
      return http.Response(
        jsonEncode(<String, dynamic>{
          'android': <String, dynamic>{
            'latest_app_version': 1,
            'min_app_version': 1,
          },
          'ios': <String, dynamic>{
            'latest_app_version': 1,
            'min_app_version': 1,
          },
          'current_season': 2024,
          'max_season': 2024,
          'is_datafeed_down': false,
          'down_events': <String>[],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    final status = await client.getStatus();
    expect(status, isNotNull);
  });

  test(
    'TbaClient throws TbaApiKeyMissingException when no key configured',
    () async {
      final client = TbaClient(
        config: InMemoryTbaConfig(),
        httpClient: MockClient((_) async => http.Response('', 200)),
      );

      await expectLater(
        client.getTeam(1234),
        throwsA(isA<TbaApiKeyMissingException>()),
      );
    },
  );

  test('TbaClient.getTeam accepts non-200 2xx success responses', () async {
    final mockClient = MockClient((_) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'key': 'frc1234',
          'team_number': 1234,
          'nickname': 'Example',
          'name': 'Example',
        }),
        201,
      );
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    final team = await client.getTeam(1234);
    expect(team, isNotNull);
    expect(team!.teamNumber, 1234);
  });

  test('TbaClient.getEventTeams decodes a list', () async {
    final mockClient = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://www.thebluealliance.com/api/v3/event/2026misjo/teams/simple',
      );
      return http.Response(
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'frc1234',
            'team_number': 1234,
            'nickname': 'Example',
            'name': 'Example',
          },
          <String, dynamic>{
            'key': 'frc2714',
            'team_number': 2714,
            'nickname': 'BattleBots',
            'name': 'BattleBots',
          },
        ]),
        200,
      );
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    final teams = await client.getEventTeams('2026misjo');
    expect(teams.map((t) => t.teamNumber), <int>[1234, 2714]);
  });

  test('TbaClient.getEventTeams returns empty list on 404', () async {
    final mockClient = MockClient((_) async {
      return http.Response('', 404);
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    final teams = await client.getEventTeams('2026misjo');
    expect(teams, isEmpty);
  });

  const sampleAvatarBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  test('TbaClient.fetchTeamAvatar decodes the avatar media item', () async {
    final mockClient = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://www.thebluealliance.com/api/v3/team/frc1234/media/2026',
      );
      return http.Response(
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'cdphotothread',
            'details': <String, dynamic>{},
          },
          <String, dynamic>{
            'type': 'avatar',
            'details': <String, dynamic>{'base64Image': sampleAvatarBase64},
          },
        ]),
        200,
      );
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    final bytes = await client.fetchTeamAvatar(1234, 2026);
    expect(bytes, isNotNull);
    expect(bytes, equals(base64Decode(sampleAvatarBase64)));
  });

  test(
    'TbaClient.fetchTeamAvatar returns null when no avatar present',
    () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'youtube',
              'details': <String, dynamic>{},
            },
          ]),
          200,
        );
      });

      final client = TbaClient(
        config: InMemoryTbaConfig('test-key'),
        httpClient: mockClient,
      );

      expect(await client.fetchTeamAvatar(1234, 2026), isNull);
    },
  );

  test('TbaClient.fetchTeamAvatar returns null on 404', () async {
    final mockClient = MockClient((_) async => http.Response('', 404));
    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );
    expect(await client.fetchTeamAvatar(99999, 2026), isNull);
  });

  test('TbaClient.getMatch sends correct path and parses videos', () async {
    final mockClient = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://www.thebluealliance.com/api/v3/match/2025flor_qm14',
      );
      return http.Response(
        jsonEncode(<String, dynamic>{
          'key': '2025flor_qm14',
          'videos': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'youtube', 'key': 'abc123'},
            <String, dynamic>{'type': 'twitch', 'key': 'def456'},
          ],
        }),
        200,
      );
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    final match = await client.getMatch('2025flor_qm14');
    expect(match, isNotNull);
    expect(match!.key, '2025flor_qm14');
    expect(match.videos.length, 2);
    expect(match.youtubeVideo, isNotNull);
    expect(match.youtubeVideo!.key, 'abc123');
    expect(
      match.youtubeVideo!.youtubeUrl,
      'https://www.youtube.com/watch?v=abc123',
    );
  });

  test('TbaClient.getMatch returns null on 404', () async {
    final mockClient = MockClient((_) async => http.Response('', 404));
    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );
    expect(await client.getMatch('nonexistent_key'), isNull);
  });

  test('TbaClient.getMatch handles match with no videos', () async {
    final mockClient = MockClient((_) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'key': '2025flor_qm1',
          'videos': <Map<String, dynamic>>[],
        }),
        200,
      );
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    final match = await client.getMatch('2025flor_qm1');
    expect(match, isNotNull);
    expect(match!.videos, isEmpty);
    expect(match.youtubeVideo, isNull);
  });
}
