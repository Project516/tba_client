# tba_client

A typed Dart client for [The Blue Alliance](https://www.thebluealliance.com) API v3. Pure Dart, so it works in Flutter apps, CLIs, and servers alike.

```dart
import 'package:tba_client/tba_client.dart';

final client = TbaClient(config: InMemoryTbaConfig('your-tba-key'));
final team = await client.getTeam(1234);
final matches = await client.getEventMatches('2026txhou');
```

Covers teams, team avatars (media), events, event team lists, and match schedules, decoded into plain Dart models. The `TbaConfig` seam decides where the `X-TBA-Auth-Key` comes from: `CompileTimeTbaConfig` reads a `--dart-define=TBA_API_KEY`, `InMemoryTbaConfig` holds one directly, and your app can implement the interface to resolve keys from anywhere (the source app chains a Firestore-stored team key). A missing key throws `TbaApiKeyMissingException` before any request goes out.

## Installation

Add the dependency in `pubspec.yaml`:

```yaml
dependencies:
  tba_client: ^0.1.0
```

Or pull the latest from Git:

```yaml
dependencies:
  tba_client:
    git: https://github.com/Project516/tba_client.git
```

## API key resolution

`TbaClient` needs a TBA auth key on every request (the `X-TBA-Auth-Key` header, preferred over the query-string form so CDN caching stays intact). Three out-of-the-box options, all injectable through `TbaConfig`:

- `CompileTimeTbaConfig` - reads `String.fromEnvironment('TBA_API_KEY')`, set via `--dart-define=TBA_API_KEY=...` or `--dart-define-from-file=tba.env`. The default for the source app.
- `InMemoryTbaConfig` - holds a key in memory; handy for tests and quick scripts. Pass `--define=TBA_API_KEY=` (or omit) to represent an empty key.
- Custom - implement `TbaConfig` yourself to resolve keys from a remote store, user settings, or a secrets manager.

```dart
final client = TbaClient(config: CompileTimeTbaConfig());
```

## API reference

`TbaClient` targets `/api/v3` on `www.thebluealliance.com`. List endpoints return an empty list on 404; single-object endpoints return `null` on 404. Anything else outside 2xx throws `TbaApiException`. `getStatus` treats 404 as a hard error so you can tell a misconfigured base URL / bad key apart from a normal "not found".

| Method | Endpoint | Returns |
| --- | --- | --- |
| `getStatus()` | `GET /status` | `TbaApiStatus` |
| `getTeam(int teamNumber)` | `GET /team/frc{n}` | `TbaTeam?` |
| `getEventTeams(String eventKey)` | `GET /event/{key}/teams/simple` | `List<TbaTeam>` |
| `fetchTeamAvatar(int teamNumber, int year)` | `GET /team/frc{n}/media/{year}` | `Uint8List?` (PNG bytes) |
| `getEvent(String eventKey)` | `GET /event/{key}` | `TbaEvent?` |
| `getEventsForYear(int year)` | `GET /events/{year}` | `List<TbaEvent>` |
| `getEventMatches(String eventKey)` | `GET /event/{key}/matches/simple` | `List<TbaScheduleMatch>` |
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

// First YouTube video attached to a match
final match = await client.getMatch('2026cmptx_f1m1');
final url = match?.youtubeVideo?.youtubeUrl;
```

### Models

- `TbaTeam` - `key`, `teamNumber`, `nickname`, `name`, and nullable `city` / `stateProv` / `country`. `displayLocation` joins the non-empty location parts with commas.
- `TbaEvent` - `key`, `name`, `year`, and optional `week` (TBA weeks are zero-based; this model offsets to one-based), `country`, `stateProv`, `startDate`, `endDate`.
- `TbaScheduleMatch` - `key`, `compLevel`, `matchNumber`, and `redTeams` / `blueTeams` as plain `int` team numbers (non-`frc`-prefixed keys are dropped). Missing `comp_level` defaults to `'qm'`.
- `TbaMatch` - `key` and a `List<TbaMatchVideo>`. `youtubeVideo` returns the first YouTube entry; `TbaMatchVideo.youtubeUrl` builds the watch URL.
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
