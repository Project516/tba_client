> **Moved.** This package now lives in [Project516/dart-packages](https://github.com/Project516/dart-packages/tree/main/packages/tba_client), tagged per release, currently `tba_client-v0.9.0`. This repo is archived and gets no further updates.

# tba_client

A typed Dart client for [The Blue Alliance](https://www.thebluealliance.com) API v3. Pure Dart, so it works in Flutter apps, CLIs, and servers alike.

```dart
import 'package:tba_client/tba_client.dart';

final client = TbaClient(config: InMemoryTbaConfig('your-tba-key'));
final team = await client.getTeam(1234);
final matches = await client.getEventMatches('2026txhou');
```

Covers teams, team avatars (media), events, event team lists, match schedules, plain OPR/DPR/CCWM, component OPR (COPRS) breakdowns, qualification rankings, playoff alliances, event awards, and TBA's own per-match predictions, decoded into plain Dart models. The `TbaConfig` seam decides where the `X-TBA-Auth-Key` comes from: `CompileTimeTbaConfig` reads a `--dart-define=TBA_API_KEY`, `InMemoryTbaConfig` holds one directly, and your app can implement the interface to resolve keys from anywhere (the source app chains a Firestore-stored team key). A missing key throws `TbaApiKeyMissingException` before any request goes out.

## API key resolution

`TbaClient` needs a TBA auth key on every request (the `X-TBA-Auth-Key` header, preferred over the query-string form so CDN caching stays intact). Three out-of-the-box options, all injectable through `TbaConfig`:

- `CompileTimeTbaConfig` - reads `String.fromEnvironment('TBA_API_KEY')`, set via `--dart-define=TBA_API_KEY=...` or `--dart-define-from-file=tba.env`. The default for the source app.
- `InMemoryTbaConfig` - holds a key in memory; handy for tests and quick scripts. Use `InMemoryTbaConfig('')` for an empty key.
- Custom - implement `TbaConfig` yourself to resolve keys from a remote store, user settings, or a secrets manager.

```dart
final client = TbaClient(config: CompileTimeTbaConfig());
```

## API reference

`TbaClient` targets `/api/v3` on `www.thebluealliance.com`. List endpoints return an empty list on 404; single-object endpoints return `null` on 404. Some event sub-resources (`getEventRankings`, `getEventAlliances`, `getEventAwards`, `getEventCoprs`, `getEventOprs`) also return `null` for a normal pre-event state (no rankings yet, no alliance selection, no awards ceremony), so a null is not an error. `getTeamAwards` returns an empty list for a team that has won nothing and for a team key TBA does not know, neither of which is an error. `getEventPredictions` is the exception to that pattern: it returns an empty map on 404 and on the `{}` TBA answers before it has enough data, which is the normal state early at an event and the permanent state at an offseason one. Anything else outside 2xx throws `TbaApiException`. `getStatus` treats 404 as a hard error so you can tell a misconfigured base URL / bad key apart from a normal "not found".

| Method | Endpoint | Returns |
| --- | --- | --- |
| `getStatus()` | `GET /status` | `TbaApiStatus` |
| `getTeam(int teamNumber)` | `GET /team/frc{n}` | `TbaTeam?` |
| `getEventTeams(String eventKey)` | `GET /event/{key}/teams/simple` | `List<TbaTeam>` |
| `fetchTeamAvatar(int teamNumber, int year)` | `GET /team/frc{n}/media/{year}` | `Uint8List?` (PNG bytes) |
| `getEvent(String eventKey)` | `GET /event/{key}` | `TbaEvent?` |
| `getEventsForYear(int year)` | `GET /events/{year}` | `List<TbaEvent>` |
| `getEventMatches(String eventKey)` | `GET /event/{key}/matches/simple` | `List<TbaScheduleMatch>` |
| `getEventMatchesDetailed(String eventKey)` | `GET /event/{key}/matches` | `List<TbaScheduleMatch>` |
| `getEventOprs(String eventKey)` | `GET /event/{key}/oprs` | `TbaEventOprs?` |
| `getEventCoprs(String eventKey)` | `GET /event/{key}/coprs` | `TbaEventCoprs?` |
| `getEventRankings(String eventKey)` | `GET /event/{key}/rankings` | `TbaEventRankings?` |
| `getEventAlliances(String eventKey)` | `GET /event/{key}/alliances` | `TbaEventAlliances?` |
| `getEventAwards(String eventKey)` | `GET /event/{key}/awards` | `TbaEventAwards?` |
| `getEventPredictions(String eventKey)` | `GET /event/{key}/predictions` | `Map<String, TbaMatchPrediction>` keyed by match key (empty for no data) |
| `getTeamAwards(int teamNumber, {int? year})` | `GET /team/frc{n}/awards[/{year}]` | `List<TbaAward>` |
| `getMatch(String matchKey)` | `GET /match/{key}` | `TbaMatch?` |

Examples:

```dart
// Team basics
final team = await client.getTeam(254);
print('${team?.teamNumber}: ${team?.nickname} (${team?.displayLocation})');

// Event schedule, alliances resolved to team numbers
final matches = await client.getEventMatches('2026cmptx');
for (final m in matches) {
  print('${m.key} red=${m.redTeams} blue=${m.blueTeams}');
}

// Event COPRS breakdown (component OPRs). The payload is stat major:
// outer key is the stat name, inner keys are team keys.
final coprs = await client.getEventCoprs('2026cmptx');
if (coprs != null) {
  final foulsFor254 = coprs['foulPoints']?['frc254'];
  print('Foul points for frc254: ${foulsFor254 ?? 'N/A'}');

  // Every component stat this event reports for one team.
  final teamStats = coprs.forTeam('frc254');
  print('Component stats for frc254: ${teamStats.keys.join(', ')}');
}

// Plain OPR, DPR and CCWM live in a separate payload (not in COPRS).
final oprs = await client.getEventOprs('2026cmptx');
if (oprs != null) {
  print('OPR for frc254: ${oprs.oprs['frc254'] ?? 'N/A'}');
}

// TBA's own predicted scores per match. Empty until TBA has enough data,
// which is normal early at an event and permanent at an offseason one.
final predictions = await client.getEventPredictions('2026cmptx');
final predicted = predictions['2026cmptx_f1m1'];
if (predicted != null) {
  print(
    '${predicted.matchKey}: red ${predicted.redScore} vs blue '
    '${predicted.blueScore}, winner ${predicted.winningAlliance} '
    '(${(predicted.probability * 100).toStringAsFixed(0)}% confidence)',
  );
}

// One team's awards. Pass a year to scope the list to a single season;
// without one you get the team's whole history.
final awards = await client.getTeamAwards(3847, year: 2025);
for (final award in awards.where((a) => a.isWinOrFinalist)) {
  print('${award.year} ${award.eventKey}: ${award.name}');
}
```

### Models

- `TbaTeam` - `key`, `teamNumber`, `nickname`, `name`, and nullable `city` / `stateProv` / `country`. `displayLocation` joins the non-empty location parts with commas.
- `TbaEvent` - `key`, `name`, `year`, and optional `week` (TBA weeks are zero-based; this model offsets to one-based), `country`, `stateProv`, `startDate`, `endDate`.
- `TbaScheduleMatch` - `key`, `compLevel`, `matchNumber`, and `redTeams` / `blueTeams` as plain `int` team numbers (non-`frc`-prefixed keys are dropped). Missing `comp_level` defaults to `'qm'`.
- `TbaEventCoprs` - component OPR breakdown. `eventKey` plus a `stats` map that is **stat major**: the outer keys are stat names and the inner keys are team keys (for example `{"foulPoints": {"frc254": 4.5}}`). Stat names vary per game year and mix human-readable labels (`Total Coral Points`) with raw camelCase (`teleopCoralPoints`), so the model carries an open map rather than named fields. `operator [](statName)` fetches a team-keyed column; `forTeam(teamKey)` returns every stat that team has as a map; `statNames` lists them; `isEmpty` reports whether any stats are present. Entries with non-numeric values are skipped individually. This endpoint carries **component** OPRs only: plain OPR, DPR and CCWM are not in this payload, use [TbaEventOprs] for those.
- `TbaEventOprs` - plain OPR, DPR and CCWM per team for an event, as three team-keyed maps (`oprs`, `dprs`, `ccwms`). Separate from `TbaEventCoprs` because TBA serves them separately and the COPRS payload has no OPR in it. `isEmpty` reports whether every section came back empty.
- `TbaEventRankings` - the qualification ranking table. `eventKey` plus `rankings` (one `TbaTeamRanking` per team in rank order) and `sortOrderNames`, the column names the payload pairs with each row's `sortOrders`. Those names are game-specific and change every season, so they are read from the payload rather than hardcoded. `sortOrdersFor(ranking)` pairs a row's values with its names for a table; extra values with no matching name are dropped. `isEmpty` reports whether any rows are present. `TbaTeamRanking` carries `teamKey`, `rank`, `teamNumber`, `wins`, `losses`, `ties`, `qualScore`, and `sortOrders` (positional).
- `TbaEventAlliances` - playoff alliances in pick order. `eventKey` plus an `alliances` list of `TbaAlliance`. The order is preserved exactly as returned and never sorted: `picks` is team keys in pick order (captain first), `captain` is the first pick (or null when empty), `status` is how far the alliance got (e.g. `f`, `sf`, or empty), and `record` is the playoff record as `wins-losses-ties`. `isEmpty` reports whether any alliances are present.
- `TbaEventAwards` - awards presented at an event. `eventKey` plus an `awards` list of `TbaAward`. `forTeam(teamKey)` returns every award that team received. `isEmpty` reports whether any awards are present.
- `TbaAward` - one award: `name`, `awardType`, `eventKey`, `year`, and `recipients` (`TbaAwardRecipient`), where a recipient may be a team, a person, or both, so team awards can be told apart from individual ones. `isWinOrFinalist` is true for TBA award types 1 and 2, the winner and finalist slots at every level of play, which separates a result from a judged or individual award. `eventKey` and `year` matter most for `getTeamAwards`, where one list spans a team's whole history and neither is implied by the call.
- `TbaMatch` - `key` and a `List<TbaMatchVideo>`. `youtubeVideo` returns the first YouTube entry; `TbaMatchVideo.youtubeUrl` builds the watch URL.
- `TbaMatchPrediction` - TBA's predicted outcome for one match (`/event/{key}/predictions`). `matchKey`, the two predicted scores (`redScore`, `blueScore`), `winningAlliance` (`red`, `blue`, or empty when the payload does not say), and `probability` (TBA's confidence in `winningAlliance`, 0 to 1, not the red alliance's chance). The per-game component means and variances that the payload also carries are renamed every season, so they are deliberately not modelled.
- `TbaApiStatus` - `currentSeason` and `maxSeason` from the `/status` endpoint.

### Exceptions

- `TbaApiKeyMissingException` - no usable key was resolved. Thrown before any network call so you can handle it as a configuration error rather than a transport one.
- `TbaApiException` - carries `statusCode` and the raw response `body`. Raised on non-2xx responses that are not 404 (or on any non-2xx for `getStatus`).

Call `client.close()` when you are done to release the underlying `http.Client`.

## Development

```sh
dart pub get
dart test
```

Tests use a mock `http.Client` (from `package:http/testing`) so they run without network access.

## License

AGPL-3.0

## Tests

Model tests assert against captured live response bodies in `test/fixtures/`,
not only hand-written maps, so a change to TBA's response shape fails a test
rather than reaching a consumer. Refresh a fixture with the `curl` in the
comment above `_fixture` in `test/live_fixtures_test.dart`.
