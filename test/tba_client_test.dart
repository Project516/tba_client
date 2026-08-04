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

  // ---------------------------------------------------------------------------
  // getEvent / getEventsForYear / getEventMatches
  // ---------------------------------------------------------------------------

  test('TbaClient.getEvent sends correct path and parses body', () async {
    final mockClient = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://www.thebluealliance.com/api/v3/event/2026txhou',
      );
      return http.Response(
        jsonEncode(<String, dynamic>{
          'key': '2026txhou',
          'name': 'FIRST In Texas District Championship',
          'year': 2026,
          'week': 5,
          'country': 'USA',
          'state_prov': 'TX',
          'start_date': '2026-03-25',
          'end_date': '2026-03-28',
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    final event = await client.getEvent('2026txhou');
    expect(event, isNotNull);
    expect(event!.key, '2026txhou');
    expect(event.name, 'FIRST In Texas District Championship');
    expect(event.year, 2026);
    // TBA weeks are zero-based; the model adds 1.
    expect(event.week, 6);
    expect(event.country, 'USA');
    expect(event.stateProv, 'TX');
    expect(event.startDate, '2026-03-25');
    expect(event.endDate, '2026-03-28');
  });

  test('TbaClient.getEvent returns null on 404', () async {
    final mockClient = MockClient((_) async => http.Response('', 404));
    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );
    expect(await client.getEvent('9999nopes'), isNull);
  });

  test('TbaClient.getEvent throws TbaApiException on server error', () async {
    final mockClient = MockClient((_) async => http.Response('boom', 500));
    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );
    await expectLater(
      client.getEvent('2026txhou'),
      throwsA(
        isA<TbaApiException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.body, 'body', 'boom'),
      ),
    );
  });

  test('TbaClient.getEventsForYear decodes a list of events', () async {
    final mockClient = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://www.thebluealliance.com/api/v3/events/2026',
      );
      return http.Response(
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'key': '2026txhou',
            'name': 'Texas District Championship',
            'year': 2026,
            'week': 5,
          },
          <String, dynamic>{
            'key': '2026mi',
            'name': 'Michigan State Championship',
            'year': 2026,
            'week': 4,
          },
        ]),
        200,
      );
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    final events = await client.getEventsForYear(2026);
    expect(events, hasLength(2));
    expect(events.first.key, '2026txhou');
    expect(events.first.week, 6); // 5 + 1 for zero-based adjustment
    expect(events[1].key, '2026mi');
    expect(events[1].week, 5); // 4 + 1
  });

  test('TbaClient.getEventsForYear returns empty list on 404', () async {
    final mockClient = MockClient((_) async => http.Response('', 404));
    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );
    expect(await client.getEventsForYear(1999), isEmpty);
  });

  test('TbaClient.getEventMatches sends correct path and parses alliances',
      () async {
    final mockClient = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://www.thebluealliance.com/api/v3/event/2026txhou/matches/simple',
      );
      return http.Response(
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'key': '2026txhou_qm1',
            'comp_level': 'qm',
            'match_number': 1,
            'alliances': <String, dynamic>{
              'red': <String, dynamic>{
                'team_keys': <String>['frc254', 'frc148', 'frc973'],
              },
              'blue': <String, dynamic>{
                'team_keys': <String>['frc195', 'frc1073', 'frc5511'],
              },
            },
          },
        ]),
        200,
      );
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    final matches = await client.getEventMatches('2026txhou');
    expect(matches, hasLength(1));
    final match = matches.single;
    expect(match.key, '2026txhou_qm1');
    expect(match.compLevel, 'qm');
    expect(match.matchNumber, 1);
    expect(match.redTeams, <int>[254, 148, 973]);
    expect(match.blueTeams, <int>[195, 1073, 5511]);
  });

  test('TbaClient.getEventMatches returns empty list on 404', () async {
    final mockClient = MockClient((_) async => http.Response('', 404));
    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );
    expect(await client.getEventMatches('doesnotexist'), isEmpty);
  });

  test('TbaClient.getEventMatches handles match with no alliances', () async {
    final mockClient = MockClient((_) async {
      return http.Response(
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'key': '2026txhou_qm2',
            'comp_level': 'qm',
            'match_number': 2,
          },
        ]),
        200,
      );
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    final matches = await client.getEventMatches('2026txhou');
    expect(matches, hasLength(1));
    final match = matches.single;
    expect(match.key, '2026txhou_qm2');
    expect(match.redTeams, isEmpty);
    expect(match.blueTeams, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // getEventCoprs
  // ---------------------------------------------------------------------------

  // The payload below is the real shape, trimmed from a live call to
  // /event/2025txhou/coprs. It is stat major: stat name outer, team key inner.
  // The first version of these tests asserted the transpose of this, which is
  // why the inverted parse shipped (#9). Note there is no OPR key -- these are
  // component OPRs, and the names are a mix of human-readable and camelCase.
  const coprsPayload = <String, dynamic>{
    'Total Coral Points': <String, dynamic>{
      'frc254': 45.2,
      'frc1678': 52.8,
    },
    'foulPoints': <String, dynamic>{'frc254': 3.1, 'frc1678': 2.0},
    'teleopCoralCount': <String, dynamic>{
      'frc254': 12.5,
      // Absent for frc1678 on purpose: not every team reports every stat.
    },
  };

  test(
    'TbaClient.getEventCoprs sends correct path and parses stat major',
    () async {
      final mockClient = MockClient((request) async {
        expect(request.headers['X-TBA-Auth-Key'], 'test-key');
        expect(
          request.url.toString(),
          'https://www.thebluealliance.com/api/v3/event/2026txhou/coprs',
        );
        return http.Response(
          jsonEncode(coprsPayload),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final client = TbaClient(
        config: InMemoryTbaConfig('test-key'),
        httpClient: mockClient,
      );

      final coprs = await client.getEventCoprs('2026txhou');
      expect(coprs, isNotNull);
      expect(coprs!.eventKey, '2026txhou');
      expect(coprs.isEmpty, isFalse);

      // Keyed by stat, not by team. A team key must not resolve as a stat.
      expect(coprs.stats, hasLength(3));
      expect(coprs.statNames, <String>[
        'Total Coral Points',
        'foulPoints',
        'teleopCoralCount',
      ]);
      expect(coprs['Total Coral Points']!['frc254'], 45.2);
      expect(coprs['foulPoints']!['frc1678'], 2.0);
      expect(
        coprs['frc254'],
        isNull,
        reason: 'a team key is not a stat name; that was the #9 inversion',
      );
      expect(coprs['nonexistent'], isNull);
    },
  );

  test('TbaEventCoprs.forTeam gathers one team across every stat', () {
    final coprs = TbaEventCoprs.fromJson('2026txhou', coprsPayload);

    expect(coprs.forTeam('frc254'), <String, num>{
      'Total Coral Points': 45.2,
      'foulPoints': 3.1,
      'teleopCoralCount': 12.5,
    });
    // Stats the team has no entry for are left out rather than zero-filled: a
    // missing component is not a component worth zero.
    expect(coprs.forTeam('frc1678'), <String, num>{
      'Total Coral Points': 52.8,
      'foulPoints': 2.0,
    });
    expect(coprs.forTeam('frc9999'), isEmpty);
  });

  test('TbaEventCoprs drops a stat whose value is not a map', () {
    final coprs = TbaEventCoprs.fromJson('2026txhou', <String, dynamic>{
      'foulPoints': <String, dynamic>{'frc254': 3.1},
      'notAMap': 'nonsense',
    });

    expect(coprs.stats, hasLength(1));
    expect(coprs['foulPoints'], <String, num>{'frc254': 3.1});
  });

  test('TbaClient.getEventCoprs returns null on 404', () async {
    final mockClient = MockClient((_) async => http.Response('', 404));
    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );
    expect(await client.getEventCoprs('doesnotexist'), isNull);
  });

  test('TbaClient.getEventCoprs returns null on HTTP 200 with null body',
      () async {
    final mockClient = MockClient((_) async => http.Response('null', 200));
    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );
    expect(await client.getEventCoprs('2026txhou'), isNull);
  });

  test('TbaClient.getEventCoprs throws TbaApiException on server error',
      () async {
    final mockClient = MockClient((_) async => http.Response('boom', 500));
    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );
    await expectLater(
      client.getEventCoprs('2026txhou'),
      throwsA(
        isA<TbaApiException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.body, 'body', 'boom'),
      ),
    );
  });

  // ---------------------------------------------------------------------------
  // getEventOprs
  // ---------------------------------------------------------------------------

  test('TbaClient.getEventOprs sends correct path and parses each section',
      () async {
    final mockClient = MockClient((request) async {
      expect(request.headers['X-TBA-Auth-Key'], 'test-key');
      expect(
        request.url.toString(),
        'https://www.thebluealliance.com/api/v3/event/2026txhou/oprs',
      );
      return http.Response(
        jsonEncode(<String, dynamic>{
          'oprs': <String, dynamic>{'frc254': 45.2, 'frc1678': 52.8},
          'dprs': <String, dynamic>{'frc254': -3.1, 'frc1678': -2.0},
          'ccwms': <String, dynamic>{'frc254': 48.3, 'frc1678': 54.8},
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );

    final oprs = await client.getEventOprs('2026txhou');
    expect(oprs, isNotNull);
    expect(oprs!.eventKey, '2026txhou');
    expect(oprs.isEmpty, isFalse);
    // This is where a plain OPR column comes from; the coprs payload has none.
    expect(oprs.oprs['frc254'], 45.2);
    expect(oprs.dprs['frc1678'], -2.0);
    expect(oprs.ccwms['frc254'], 48.3);
  });

  test('TbaEventOprs tolerates missing or malformed sections', () {
    final oprs = TbaEventOprs.fromJson('2026txhou', <String, dynamic>{
      'oprs': <String, dynamic>{'frc254': 45.2, 'frc1678': 'nonsense'},
      // dprs absent entirely, ccwms the wrong type.
      'ccwms': 'nonsense',
    });

    expect(oprs.oprs, <String, num>{'frc254': 45.2});
    expect(oprs.dprs, isEmpty);
    expect(oprs.ccwms, isEmpty);
    expect(oprs.isEmpty, isFalse);
  });

  test('TbaClient.getEventOprs returns null on 404', () async {
    final mockClient = MockClient((_) async => http.Response('', 404));
    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );
    expect(await client.getEventOprs('doesnotexist'), isNull);
  });

  test('TbaClient.getEventOprs returns null on HTTP 200 with null body',
      () async {
    final mockClient = MockClient((_) async => http.Response('null', 200));
    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );
    expect(await client.getEventOprs('2026txhou'), isNull);
  });

  test('TbaClient.getEventOprs throws TbaApiException on server error',
      () async {
    final mockClient = MockClient((_) async => http.Response('boom', 500));
    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );
    await expectLater(
      client.getEventOprs('2026txhou'),
      throwsA(
        isA<TbaApiException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.body, 'body', 'boom'),
      ),
    );
  });

  test('TbaEventCoprs.fromJson parses an empty breakdown as empty', () {
    // An empty top-level object ({}) still deserializes into a (zero-stat)
    // TbaEventCoprs rather than null; the null path is only for 404.
    final coprs = TbaEventCoprs.fromJson('2026txhou', <String, dynamic>{});
    expect(coprs.eventKey, '2026txhou');
    expect(coprs.isEmpty, isTrue);
    expect(coprs.stats, isEmpty);
    expect(coprs.statNames, isEmpty);
    expect(coprs.forTeam('frc254'), isEmpty);
  });

  test('TbaEventCoprs.fromJson skips non-numeric team values', () {
    // Stat major throughout: outer keys are stat names, inner keys are teams.
    final coprs = TbaEventCoprs.fromJson('2026txhou', <String, dynamic>{
      'foulPoints': <String, dynamic>{
        'frc254': 45.2,
        'frc9999': 'not a number',
        'frc1678': 12.5,
      },
      'teleopCoralCount': <String, dynamic>{
        'frc254': 'unavailable',
      },
      'Total Coral Points': <String, dynamic>{
        'frc254': 1.0,
      },
    });
    expect(coprs.stats, hasLength(3));
    // Numeric entries are kept; the string gets dropped from the inner map.
    expect(coprs['foulPoints']!, hasLength(2));
    expect(coprs['foulPoints']!['frc254'], 45.2);
    expect(coprs['foulPoints']!['frc1678'], 12.5);
    expect(coprs['foulPoints']!.containsKey('frc9999'), isFalse);
    // Every team dropped leaves an empty (but present) inner map, so the stat
    // still shows up in a column picker even though nobody has a value yet.
    expect(coprs['teleopCoralCount']!, isEmpty);
    expect(coprs['Total Coral Points']!['frc254'], 1.0);
    // The dropped entry is dropped from the team view too, not zero-filled.
    expect(coprs.forTeam('frc9999'), isEmpty);
  });

  // ---------------------------------------------------------------------------
  // Model parsing edge cases
  // ---------------------------------------------------------------------------

  test('TbaScheduleMatch.fromJson parses full alliances', () {
    final match = TbaScheduleMatch.fromJson(<String, dynamic>{
      'key': '2025flor_f1m1',
      'comp_level': 'f',
      'match_number': 1,
      'alliances': <String, dynamic>{
        'red': <String, dynamic>{
          'team_keys': <String>['frc254', 'frc1678'],
        },
        'blue': <String, dynamic>{
          'team_keys': <String>['frc118', 'frc2425'],
        },
      },
    });
    expect(match.compLevel, 'f');
    expect(match.matchNumber, 1);
    expect(match.redTeams, <int>[254, 1678]);
    expect(match.blueTeams, <int>[118, 2425]);
  });

  test('TbaScheduleMatch.fromJson defaults comp_level to qm when missing', () {
    final match = TbaScheduleMatch.fromJson(<String, dynamic>{
      'key': '2025flor_qm3',
      'match_number': 3,
    });
    expect(match.compLevel, 'qm');
    expect(match.matchNumber, 3);
    expect(match.redTeams, isEmpty);
    expect(match.blueTeams, isEmpty);
  });

  test('TbaScheduleMatch.fromJson skips non-frc prefixed team keys', () {
    final match = TbaScheduleMatch.fromJson(<String, dynamic>{
      'key': '2025flor_qm4',
      'comp_level': 'qm',
      'match_number': 4,
      'alliances': <String, dynamic>{
        'red': <String, dynamic>{
          'team_keys': <String>['frc254', 'not-a-team', 'frc0'],
        },
      },
    });
    // 'not-a-team' falls back to 0 (dropped), 'frc0' is dropped (t > 0 guard).
    expect(match.redTeams, <int>[254]);
  });

  test('TbaEvent.fromJson offsets week from zero-based to one-based', () {
    final event = TbaEvent.fromJson(<String, dynamic>{
      'key': '2026txhou',
      'name': 'Texas DCMP',
      'year': 2026,
      'week': 0,
    });
    expect(event.week, 1);
  });

  test('TbaEvent.fromJson leaves week null when absent', () {
    final event = TbaEvent.fromJson(<String, dynamic>{
      'key': '2026txhou',
      'name': 'Texas DCMP',
      'year': 2026,
    });
    expect(event.week, isNull);
  });

  test('TbaEvent.fromJson defaults year to 0 when missing or invalid', () {
    final noYear = TbaEvent.fromJson(<String, dynamic>{
      'key': 'k',
      'name': 'n',
    });
    expect(noYear.year, 0);

    final badYear = TbaEvent.fromJson(<String, dynamic>{
      'key': 'k',
      'name': 'n',
      'year': 'not a number',
    });
    expect(badYear.year, 0);
  });

  // ---------------------------------------------------------------------------
  // close()
  // ---------------------------------------------------------------------------

  test('TbaClient.close closes the underlying http client', () {
    final requests = <http.Request>[];
    final mockClient = MockClient((request) async {
      requests.add(request);
      return http.Response('{}', 200);
    });

    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: mockClient,
    );
    // Should not throw.
    client.close();
  });
}
