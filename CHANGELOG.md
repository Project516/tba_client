# Changelog

## 0.5.1

- No API change. Adds coverage for the empty-key guard and for award and
  alliance payloads that arrive as something other than a list, so the tagged
  version and its tests match.

## 0.5.0

- `getEventMatchesDetailed`, reading `GET /event/{key}/matches`. The `simple`
  payload `getEventMatches` reads carries no `videos` and no `score_breakdown`,
  so `TbaScheduleMatch` always parsed those as empty no matter the event. Kept as
  a separate call rather than switching `getEventMatches` over: a score breakdown
  is large, and the schedule is refetched on every event change and every
  pull-to-refresh.

## 0.4.0

- `TbaScheduleMatch` now carries the rest of the match payload it was dropping:
  `redScore`/`blueScore`, `winningAlliance`, `scheduledTime`/`predictedTime`/
  `actualTime`, `videos`, and the game-specific `scoreBreakdown`. An unplayed
  match reports null scores rather than TBA's `-1`, and `isPlayed`/`isTie`
  separate "no result yet" from a genuine tie, which a bare
  `winning_alliance` cannot (both are an empty string).
- Add `getEventRankings` and `TbaEventRankings`/`TbaTeamRanking` for
  `/event/{key}/rankings`. Sort-order values are positional and game specific,
  so `sortOrdersFor` pairs them with the payload's own `sort_order_info` names
  rather than hardcoding a season's columns.
- Add `getEventAlliances` and `TbaEventAlliances`/`TbaAlliance` for
  `/event/{key}/alliances`. Pick order is preserved and never sorted.
- Add `getEventAwards` and `TbaEventAwards`/`TbaAward` for
  `/event/{key}/awards`, distinguishing team awards from individual ones.
- `TbaMatchVideo.listFromJson` is shared by `TbaMatch` and
  `TbaScheduleMatch` so the two cannot drift.

Additive: no existing field or method changed shape (#11).

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
