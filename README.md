# tba_client

A typed Dart client for [The Blue Alliance](https://www.thebluealliance.com) API v3. Pure Dart, so it works in Flutter apps, CLIs, and servers alike.

```dart
import 'package:tba_client/tba_client.dart';

final client = TbaClient(config: InMemoryTbaConfig('your-tba-key'));
final team = await client.getTeam(1234);
final matches = await client.getEventMatches('2026txhou');
```

Covers teams, team avatars (media), events, event team lists, and match schedules, decoded into plain Dart models. The `TbaConfig` seam decides where the `X-TBA-Auth-Key` comes from: `CompileTimeTbaConfig` reads a `--dart-define=TBA_API_KEY`, `InMemoryTbaConfig` holds one directly, and your app can implement the interface to resolve keys from anywhere (the source app chains a Firestore-stored team key). A missing key throws `TbaApiKeyMissingException` before any request goes out.

## License

AGPL-3.0
