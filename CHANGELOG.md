# Changelog

## 0.3.0

- **Breaking:** `TbaEventCoprs` now parses the COPRS payload the way the
  endpoint actually sends it. `/event/{key}/coprs` is **stat major** (stat name
  outer, team key inner); 0.2.0 read the outer keys as team keys, so every
  lookup missed. `stats` is now stat name -> team key -> value, `operator []`
  takes a stat name, and `statNames` lists what the event reports. Use the new
  `forTeam(teamKey)` for the per-team view 0.2.0 claimed to provide (#9).
- Add `getEventOprs` and `TbaEventOprs` for `/event/{key}/oprs`: plain OPR,
  DPR and CCWM per team. These are **not** in the COPRS payload, so an OPR
  column needs this call (#9).

## 0.2.0

- Add `getEventCoprs` method to fetch component OPR (COPRS) breakdown for an
  event, needed by SpectrumStrategy. The COPRS response varies by game year,
  so `TbaEventCoprs` exposes an open `Map<String, Map<String, num>>` keyed by
  team key and stat name (OPR, DPR, Foul Points, etc.). Superseded by 0.3.0:
  the shape was wrong, see #9.

## 0.1.0

- Initial release: `TbaClient` (`getStatus`, `getTeam`, `getEventTeams`,
  `fetchTeamAvatar`, `getEvent`, `getEventsForYear`, `getEventMatches`,
  `getMatch`) with typed models and pluggable API key resolution through
  `TbaConfig` (`CompileTimeTbaConfig` built in).
