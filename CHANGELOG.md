# Changelog

## Unreleased

- Add test coverage for `getEvent`, `getEventsForYear`, `getEventMatches`,
  `TbaScheduleMatch`/`TbaEvent` JSON parsing, and `close()`.
- Fix `TbaEvent.fromJson` crashing on a non-numeric `year` field. The cast
  `(json['year'] as num?)` threw a `TypeError` for unexpected payloads; it now
  falls back to `0` like the `week` field does.

## 0.1.0

- Initial release: `TbaClient` (`getTeam`, `getTeams`, `getEventMatches`,
  `getEventTeams`, `fetchTeamAvatar`) with typed models and pluggable API
  key resolution through `TbaConfig` (`CompileTimeTbaConfig` built in).
