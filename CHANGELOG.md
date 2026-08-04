# Changelog

## 0.2.0

- Add `getEventCoprs` method to fetch component OPR (COPRS) breakdown for an
  event, needed by SpectrumStrategy. The COPRS response varies by game year,
  so `TbaEventCoprs` exposes an open `Map<String, Map<String, num>>` keyed by
  team key and stat name (OPR, DPR, Foul Points, etc.).

## 0.1.0

- Initial release: `TbaClient` (`getStatus`, `getTeam`, `getEventTeams`,
  `fetchTeamAvatar`, `getEvent`, `getEventsForYear`, `getEventMatches`,
  `getMatch`) with typed models and pluggable API key resolution through
  `TbaConfig` (`CompileTimeTbaConfig` built in).
