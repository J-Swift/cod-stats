#!/usr/bin/env bash

set -euo pipefail

readonly sourcedir="${COD_DATADIR}/parser/output"
readonly outdir_staging=$(mktemp -d)
readonly outdir_staging_data="${outdir_staging}/data/output"
readonly outdir_dest="${COD_DATADIR}/frontend/output"

readonly dbfile="${sourcedir}/data.sqlite"

readonly debug_out=false

die() {
  local -r msg="${1}"

  echo "ERROR: ${msg}"
  exit 1
}

if [ ! -f "${dbfile}" ]; then
  die "no db found at [${dbfile}]"
fi

if [ ! -d "${outdir_staging}" ]; then
  die "no directory found at [${outdir_staging}]"
fi

mkdir -p "${outdir_dest}"
mkdir -p "${outdir_staging_data}"

### SQL

get_player_ids() {
  sqlite3 "${dbfile}" <<-EOF
SELECT player_id FROM players ORDER BY player_id;
EOF
}

get_ts() {
  echo $(date +%s%N | cut -b1-13)
}

report_file_written() {
  local -r outpath="${1}"
  local -r start_ts="${2}"
  local -r end_ts="${3}"

  echo "wrote [$(basename "${outpath}")] in [$((end_ts - start_ts))ms]"
}

###

write_meta() {
  local start=$(get_ts)
  cp ../config/players.json "${outdir_staging_data}/players.json"
  local end=$(get_ts)
  report_file_written "${outdir_staging_data}/players.json" "${start}" "${end}"

  local start=$(get_ts)
  local -r ts=$(get_ts)
  echo "{\"updatedAt\": ${ts}}" >"${outdir_staging_data}/meta.json"
  local end=$(get_ts)
  report_file_written "${outdir_staging_data}/meta.json" "${start}" "${end}"

  local start=$(get_ts)
  local -r data_seasons=$(
    sqlite3 "${dbfile}" <<-EOF
WITH cte_seasons AS (
  SELECT row_number() OVER (ORDER BY start DESC) rn, * FROM vw_seasons ORDER BY sort_order
)

SELECT
  json_object(
    'current', (SELECT id FROM cte_seasons WHERE rn=1),
    'seasons', json_group_array(
      json_object(
        'id', id,
        'desc', desc,
        'start', start,
        'end', end
      )
    )
  ) meta
FROM cte_seasons;
EOF
  )
  echo "${data_seasons}" >"${outdir_staging_data}/seasons.json"
  local end=$(get_ts)
  report_file_written "${outdir_staging_data}/seasons.json" "${start}" "${end}"
}

write_leaderboards() {
  local -r num_results=10

  local start=$(get_ts)
  local data_leaderboard=$(
    sqlite3 "${dbfile}" <<-EOF
WITH

cte_mostkills as (
  SELECT json_object(
    'date_key', date_key,
    'game_mode_sub', game_mode_sub,
    'game_id', game_id,
    'player_id', player_id,
    'value', kills
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * FROM vw_core_players) AND
    1
  ORDER BY
    kills DESC
  LIMIT ${num_results}
),

cte_mostdeaths as (
  SELECT json_object(
    'date_key', date_key,
    'game_mode_sub', game_mode_sub,
    'game_id', game_id,
    'player_id', player_id,
    'value', deaths
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * FROM vw_core_players) AND
    1
  ORDER BY
    deaths DESC
  LIMIT ${num_results}
),

cte_highestkd as (
  SELECT json_object(
    'date_key', date_key,
    'game_mode_sub', game_mode_sub,
    'game_id', game_id,
    'player_id', player_id,
    'value', kdRatio
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * FROM vw_core_players) AND
    1
  ORDER BY
    kdRatio DESC
  LIMIT ${num_results}
),

cte_damagedone as (
  SELECT json_object(
    'date_key', date_key,
    'game_mode_sub', game_mode_sub,
    'game_id', game_id,
    'player_id', player_id,
    'value', damageDone
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * FROM vw_core_players) AND
    1
  ORDER BY
    damageDone DESC
  LIMIT ${num_results}
),

cte_damagetaken as (
  SELECT json_object(
    'date_key', date_key,
    'game_mode_sub', game_mode_sub,
    'game_id', game_id,
    'player_id', player_id,
    'value', damageTaken
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * FROM vw_core_players) AND
    1
  ORDER BY
    damageTaken DESC
  LIMIT ${num_results}
),

cte_highestscore as (
  SELECT json_object(
    'date_key', date_key,
    'game_mode_sub', game_mode_sub,
    'game_id', game_id,
    'player_id', player_id,
    'value', score
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * FROM vw_core_players) AND
    1
  ORDER BY
    score DESC
  LIMIT ${num_results}
),

cte_mostdistance as (
  SELECT json_object(
    'date_key', date_key,
    'game_mode_sub', game_mode_sub,
    'game_id', game_id,
    'player_id', player_id,
    'value', cast((distanceTraveled / 1000) as int) || ' km'
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * FROM vw_core_players) AND
    1
  ORDER BY
    distanceTraveled DESC
  LIMIT ${num_results}
),

cte_mostheadshots as (
  SELECT json_object(
    'date_key', date_key,
    'game_mode_sub', game_mode_sub,
    'game_id', game_id,
    'player_id', player_id,
    'value', headshots
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * FROM vw_core_players) AND
    1
  ORDER BY
    headshots DESC
  LIMIT ${num_results}
),

cte_mostlootboxes as (
  SELECT json_object(
    'date_key', date_key,
    'game_mode_sub', game_mode_sub,
    'game_id', game_id,
    'player_id', player_id,
    'value', objectiveBrCacheOpen
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * FROM vw_core_players) AND
    1
  ORDER BY
    objectiveBrCacheOpen DESC
  LIMIT ${num_results}
),

cte_mostrevives as (
  SELECT json_object(
    'date_key', date_key,
    'game_mode_sub', game_mode_sub,
    'game_id', game_id,
    'player_id', player_id,
    'value', objectiveReviver
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * FROM vw_core_players) AND
    1
  ORDER BY
    objectiveReviver DESC
  LIMIT ${num_results}
),

cte_mostdowns as (
  SELECT json_object(
    'date_key', date_key,
    'game_mode_sub', game_mode_sub,
    'game_id', game_id,
    'player_id', player_id,
    'value', objectiveBrDownAll
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * FROM vw_core_players) AND
    1
  ORDER BY
    objectiveBrDownAll DESC
  LIMIT ${num_results}
),

cte_mostvehiclesdestroyed as (
  SELECT json_object(
    'date_key', date_key,
    'game_mode_sub', game_mode_sub,
    'game_id', game_id,
    'player_id', player_id,
    'value', objectiveDestroyedVehicleAll
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * FROM vw_core_players) AND
    1
  ORDER BY
    objectiveDestroyedVehicleAll DESC
  LIMIT ${num_results}
),

cte_null as (SELECT 1)

SELECT json_array(
  (select json_object('title', 'Kills',
                      'meta', json_group_array(json(meta))) FROM cte_mostkills),
  (select json_object('title', 'K/D',
                      'meta', json_group_array(json(meta))) FROM cte_highestkd),
  (select json_object('title', 'Damage done',
                      'meta', json_group_array(json(meta))) FROM cte_damagedone),
  (select json_object('title', 'Downs',
                      'meta', json_group_array(json(meta))) FROM cte_mostdowns),
  (select json_object('title', 'Revives',
                      'meta', json_group_array(json(meta))) FROM cte_mostrevives),
  (select json_object('title', 'Vehicles destroyed',
                      'meta', json_group_array(json(meta))) FROM cte_mostvehiclesdestroyed),
  (select json_object('title', 'Boxes looted',
                      'meta', json_group_array(json(meta))) FROM cte_mostlootboxes),
  (select json_object('title', 'Score',
                      'meta', json_group_array(json(meta))) FROM cte_highestscore),
  (select json_object('title', 'Headshots',
                      'meta', json_group_array(json(meta))) FROM cte_mostheadshots),
  (select json_object('title', 'Distance traveled',
                      'meta', json_group_array(json(meta))) FROM cte_mostdistance),
  (select json_object('title', 'Deaths',
                      'meta', json_group_array(json(meta))) FROM cte_mostdeaths),
  (select json_object('title', 'Damage taken',
                      'meta', json_group_array(json(meta))) FROM cte_damagetaken)
) as leaderboard;
EOF
  )

  local outpath="${outdir_staging_data}/leaderboard_bygame.json"
  echo "${data_leaderboard}" >"${outpath}"
  local end=$(get_ts)
  report_file_written "${outpath}" "${start}" "${end}"

  local start=$(get_ts)
  local data_leaderboard=$(
    sqlite3 "${dbfile}" <<-EOF
WITH

cte_gulag_by_kills AS (
  SELECT
    (
      -- https://dba.stackexchange.com/a/254178
      DENSE_RANK() OVER (PARTITION BY player_id ORDER BY date_key)  - DENSE_RANK() OVER (PARTITION BY player_id, gulagKills ORDER BY date_key)
    ) AS gulag_group,
    gulagKills, gulagDeaths, date_key, game_id, player_id, stats
  FROM vw_stats_wz
  WHERE
    player_id IN (SELECT * from vw_core_players) AND
    (gulagKills=1 OR gulagDeaths=1) AND
    1
),
cte_gulag_by_deaths AS (
  SELECT
    (
      -- https://dba.stackexchange.com/a/254178
      DENSE_RANK() OVER (PARTITION BY player_id ORDER BY date_key)  - DENSE_RANK() OVER (PARTITION BY player_id, gulagDeaths ORDER BY date_key)
    ) AS gulag_group,
    gulagKills, gulagDeaths, date_key, game_id, player_id, stats
  FROM vw_stats_wz
  WHERE
    player_id IN (SELECT * from vw_core_players) AND
    (gulagKills=1 OR gulagDeaths=1) AND
    1
),

cte_consecutive_gulag_kills as (
  SELECT json_object(
    'date_key', min(date_key),
    'until_date_key', max(date_key),
    'game_mode_sub', null,
    'game_id', null,
    'player_id', player_id,
    'value', count(1)
  ) AS meta
    FROM cte_gulag_by_kills
    WHERE gulagKills=1
    GROUP BY player_id, gulag_group
    ORDER BY count(1) desc
    LIMIT ${num_results}
),
cte_consecutive_gulag_deaths as (
  SELECT json_object(
    'date_key', min(date_key),
    'until_date_key', max(date_key),
    'game_mode_sub', null,
    'game_id', null,
    'player_id', player_id,
    'value', count(1)
  ) AS meta
  FROM cte_gulag_by_deaths
  WHERE gulagDeaths=1
  GROUP BY player_id, gulag_group
  ORDER BY count(1) desc
  LIMIT ${num_results}
),

cte_most_lastplaces as (
  SELECT json_object(
    'date_key', null,
    'game_mode_sub', null,
    'game_id', null,
    'player_id', player_id,
    'value', count(1)
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * from vw_core_players) AND
    teamPlacement=numberOfTeams AND
    1
  GROUP BY
    player_id
  ORDER BY
    count(1) DESC
  LIMIT ${num_results}
),

cte_most_wins as (
  SELECT json_object(
    'date_key', null,
    'game_mode_sub', null,
    'game_id', null,
    'player_id', player_id,
    'value', count(1)
  ) AS meta
  FROM
    vw_stats_wz
  WHERE
    player_id IN (SELECT * from vw_core_players) AND
    teamPlacement=1 AND
    1
  GROUP BY
    player_id
  ORDER BY
    count(1) DESC
  LIMIT ${num_results}
),

cte_null as (SELECT 1)

SELECT json_array(
  (select json_object('title', 'Consecutive gulag wins',
                      'meta', json_group_array(json(meta))) FROM cte_consecutive_gulag_kills),
  (select json_object('title', 'Consecutive gulag losses',
                      'meta', json_group_array(json(meta))) FROM cte_consecutive_gulag_deaths),
  (select json_object('title', 'Total wins',
                      'meta', json_group_array(json(meta))) FROM cte_most_wins),
  (select json_object('title', 'Total last places',
                      'meta', json_group_array(json(meta))) FROM cte_most_lastplaces)
) as leaderboard;
EOF
  )

  local outpath="${outdir_staging_data}/leaderboard_lifetime.json"
  echo "${data_leaderboard}" >"${outpath}"
  local end=$(get_ts)
  report_file_written "${outpath}" "${start}" "${end}"

  local start=$(get_ts)
  local data_leaderboard=$(
    sqlite3 "${dbfile}" <<-EOF
select group_concat(leaderboards) from (
  select json_object(
    'mode',
      case category
      when 'wz_solo' then 'Solo'
      when 'wz_duos' then 'Duos'
      when 'wz_trios' then 'Trios'
      when 'wz_quads' then 'Quads'
      else category
      END,
    'sortOrder',
      case category
      when 'wz_quads' then 1
      when 'wz_solo' then 2
      when 'wz_duos' then 3
      when 'wz_trios' then 4
      else 99
      END,
    'stats', json_group_array(jsonStats)
  ) leaderboards from vw_team_stat_breakdowns group by category
);
EOF
  )

  local outpath="${outdir_staging_data}/team_leaderboards.json"
  echo "[" >"${outpath}"
  echo "${data_leaderboard}" >>"${outpath}"
  echo "]" >>"${outpath}"
  local end=$(get_ts)
  report_file_written "${outpath}" "${start}" "${end}"
  echo
}

write_recent_matches() {
  local -r num_results=15

  local start=$(get_ts)
  local data_recent_matches=$(
    sqlite3 "${dbfile}" <<-EOF
WITH cte_recent_stats AS (
  SELECT
    json_object(
      'date', date_key,
      'game_id', game_id,
      'game_mode', ifnull(vgm.display_name, 'Unknown &lt;' || game_mode_sub || '&gt;'),
      'player_ids', player_ids,
      'player_stats', json(player_stats)
    ) stats
  FROM
    vw_full_game_stats
  LEFT JOIN
    vw_game_modes vgm ON vgm.id=game_mode_sub
  ORDER BY
    date_key DESC
)

SELECT group_concat(stats) FROM (select * from cte_recent_stats LIMIT ${num_results});
EOF
  )

  local outpath="${outdir_staging_data}/recent_matches.json"
  echo "[" >"${outpath}"
  echo "${data_recent_matches}" >>"${outpath}"
  echo "]" >>"${outpath}"
  local end=$(get_ts)
  report_file_written "${outpath}" "${start}" "${end}"

  echo
}

write_recent_sessions() {
  local start=$(get_ts)
  local data_recent_sessions=$(
    sqlite3 "${dbfile}" <<-EOF
with cte_last_session_stats AS (
  select * from (
    select
      row_number() over (PARTITION by player_id order by session_number desc) rn,
      *
      FROM vw_player_sessions_with_stats
  ) vsw where rn=1
)

select group_concat(
  json_object(
    'player_id', player_id,
    'stats', json(stats)
  )
) from cte_last_session_stats;
EOF
  )

  local outpath="${outdir_staging_data}/recent_sessions.json"
  echo "[" >"${outpath}"
  echo "${data_recent_sessions}" >>"${outpath}"
  echo "]" >>"${outpath}"
  local end=$(get_ts)
  report_file_written "${outpath}" "${start}" "${end}"

  echo
}

write_player_rollup_stats_to_json() {
  local -r name="${1}"
  local -r outpath="${2}"

  local -r stats=$(
    sqlite3 "${dbfile}" <<-EOF
WITH
  cte_stats_by_season AS (
    SELECT
      id,
      sort_order,
      desc,
      player_id,
      sum(1) matchesPlayed,
      sum(damageDone) damageDone,
      sum(kills) kills,
      sum(deaths) deaths,
      sum(gulagKills) gulagKills,
      sum(gulagDeaths) gulagDeaths
    FROM vw_seasons vs
    JOIN
      vw_stats_wz vsw ON vsw.date_key >= vs.start AND vsw.date_key <= vs.end
    GROUP BY
      vsw.player_id, vs.id
    ORDER BY player_id, sort_order
  ),
  cte_stats_rollup AS (
    SELECT
      player_id,
      id,
      desc,
      sort_order,
      json_array(
        json_object(
          'name', 'K/D',
          'value', round(kills/cast(deaths as float), 2)
        ),
        json_object(
          'name', 'Avg Kills',
          'value', round(kills/cast(matchesPlayed as float), 2)
        ),
        json_object(
          'name', 'Dmg/Kill',
          'value', cast(damageDone/kills as int)
        ),
        json_object(
          'name', 'Gulag',
          'value', cast(100 * gulagKills/cast(gulagKills + gulagDeaths as float) as int) || '%'
        )
      ) stats
    from cte_stats_by_season
    ORDER BY player_id, sort_order
  ),

  cte_placements_by_season AS (
    SELECT
      vs.id,
      sort_order,
      desc,
      player_id,
      vgm.category,
      round(100 * sum(teamPlacement)/cast(sum(numberOfTeams) as float), 2) avgPlacement
    FROM vw_seasons vs
    JOIN
      vw_stats_wz vsw ON vsw.date_key >= vs.start AND vsw.date_key <= vs.end,
      vw_game_modes vgm ON vgm.id=vsw.game_mode_sub
    GROUP BY
      vsw.player_id, vs.id, vgm.category
    ORDER BY
      player_id, sort_order
  ),
  cte_placements_rollup AS (
    SELECT
      'placements' AS 'result_type',
      player_id,
      id,
      desc,
      sort_order,
      json_array(
        json_object(
          'name', 'Avg Solo',
          'value', IFNULL(MAX(CASE WHEN category='wz_solo' THEN avgPlacement  END), 'N/A')
        ),
        json_object(
          'name', 'Avg Duos',
          'value', IFNULL(MAX(CASE WHEN category='wz_duos' THEN avgPlacement  END), 'N/A')
        ),
        json_object(
          'name', 'Avg Trios',
          'value', IFNULL(MAX(CASE WHEN category='wz_trios' THEN avgPlacement  END), 'N/A')
        ),
        json_object(
          'name', 'Avg Quads',
          'value', IFNULL(MAX(CASE WHEN category='wz_quads' THEN avgPlacement  END), 'N/A')
        )
      ) stats
    FROM cte_placements_by_season
    GROUP BY
      player_id, id
    ORDER BY
      player_id, sort_order
  )

SELECT
  json_group_array(
    json_object(
      'season_id', csr.id,
      'displayName', csr.desc,
      'metrics', json(csr.stats),
      'placements', json(cpr.stats)
    )
  ) stats
FROM cte_stats_rollup csr
JOIN cte_placements_rollup cpr USING (player_id, id)
WHERE csr.player_id='${name}'
GROUP BY csr.player_id
EOF
  )

  echo "${stats}" >"${outpath}"
}

write_player_time_stats_to_json() {
  local -r name="${1}"
  local -r start="${2}"
  local -r end="${3}"
  local -r outpath="${4}"

  local -r stats=$(
    sqlite3 "${dbfile}" <<-EOF
WITH cte_stats AS (
 SELECT
  json_object(
    'date', date(date_key),
    'stats', json_object(
      'raw', json_object(
        'matchesPlayed', matchesPlayed,
        'kills', kills,
        'deaths', deaths,
        'gulagKills', gulagKills,
        'gulagDeaths', gulagDeaths,
        'headshots', headshots,
        'damageDone', damageDone,
        'distanceTraveled', distanceTraveled,
        'kdRatio', kdRatio,
        'scorePerMinute', scorePerMinute,
        'monsters', monsters,
        'gooseeggs', gooseeggs
      ),
      'smoothed_3', json_object(
        'matchesPlayed', sum(matchesPlayed) OVER(ORDER BY date_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        'kills', sum(kills) OVER(ORDER BY date_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        'deaths', sum(deaths) OVER(ORDER BY date_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        'gulagKills', sum(gulagKills) OVER(ORDER BY date_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        'gulagDeaths', sum(gulagDeaths) OVER(ORDER BY date_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        'headshots', sum(headshots) OVER(ORDER BY date_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        'damageDone', sum(damageDone) OVER(ORDER BY date_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        'distanceTraveled', sum(distanceTraveled) OVER(ORDER BY date_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        'kdRatio', avg(kdRatio) OVER(ORDER BY date_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        'scorePerMinute', avg(scorePerMinute) OVER(ORDER BY date_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        'monsters', sum(monsters) OVER(ORDER BY date_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        'gooseeggs', sum(gooseeggs) OVER(ORDER BY date_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
      ),
      'smoothed_7', json_object(
        'matchesPlayed', sum(matchesPlayed) OVER(ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
        'kills', sum(kills) OVER(ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
        'deaths', sum(deaths) OVER(ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
        'gulagKills', sum(gulagKills) OVER(ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
        'gulagDeaths', sum(gulagDeaths) OVER(ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
        'headshots', sum(headshots) OVER(ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
        'damageDone', sum(damageDone) OVER(ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
        'distanceTraveled', sum(distanceTraveled) OVER(ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
        'kdRatio', avg(kdRatio) OVER(ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
        'scorePerMinute', avg(scorePerMinute) OVER(ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
        'monsters', sum(monsters) OVER(ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
        'gooseeggs', sum(gooseeggs) OVER(ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
      ),
      'cumalative', json_object(
        'matchesPlayed', sum(matchesPlayed) OVER(ORDER BY date_key),
        'kills', sum(kills) OVER(ORDER BY date_key),
        'deaths', sum(deaths) OVER(ORDER BY date_key),
        'gulagKills', sum(gulagKills) OVER(ORDER BY date_key),
        'gulagDeaths', sum(gulagDeaths) OVER(ORDER BY date_key),
        'headshots', sum(headshots) OVER(ORDER BY date_key),
        'damageDone', sum(damageDone) OVER(ORDER BY date_key),
        'distanceTraveled', sum(distanceTraveled) OVER(ORDER BY date_key),
        'kdRatio', avg(kdRatio) OVER(ORDER BY date_key),
        'scorePerMinute', avg(scorePerMinute) OVER(ORDER BY date_key),
        'monsters', sum(monsters) OVER(ORDER BY date_key),
        'gooseeggs', sum(gooseeggs) OVER(ORDER BY date_key)
      )
    )
  ) as stats
  FROM
    vw_player_stats_by_day_wz
  WHERE
    player_id='${name}' AND
    date_key>='${start}' AND
    date_key<='${end}' AND
    1
  ORDER BY
    date_key
)

select json_group_array(stats) 'stats' from cte_stats
EOF
  )

  echo "${stats}" >"${outpath}"
}

write_player_game_stats_to_json() {
  local -r name="${1}"
  local -r start="${2}"
  local -r end="${3}"
  local -r outpath="${4}"

  local -r stats=$(
    sqlite3 "${dbfile}" <<-EOF
WITH cte_stats AS (
 SELECT
  json_object(
    'date',  date_key,
    'stats', json_object(
      'raw', json_object(
        'matchesPlayed', matchesPlayed,
        'mode', mode,
        'numberOfPlayers', numberOfPlayers,
        'numberOfTeams', numberOfTeams,
        'teamPlacement', teamPlacement,
        'kills', kills,
        'deaths', deaths,
        'gulagKills', gulagKills,
        'gulagDeaths', gulagDeaths,
        'headshots', headshots,
        'damageDone', damageDone,
        'distanceTraveled', distanceTraveled,
        'kdRatio', kdRatio,
        'scorePerMinute', scorePerMinute,
        'monsters', monsters,
        'gooseeggs', gooseeggs
      ),
      'smoothed_10', json_object(
        'matchesPlayed', count(matchesPlayed) OVER(ORDER BY date_key ROWS BETWEEN 9 PRECEDING AND CURRENT ROW),
        'kills', sum(kills) OVER(ORDER BY date_key ROWS BETWEEN 9 PRECEDING AND CURRENT ROW),
        'deaths', sum(deaths) OVER(ORDER BY date_key ROWS BETWEEN 9 PRECEDING AND CURRENT ROW),
        'gulagKills', sum(gulagKills) OVER(ORDER BY date_key ROWS BETWEEN 9 PRECEDING AND CURRENT ROW),
        'gulagDeaths', sum(gulagDeaths) OVER(ORDER BY date_key ROWS BETWEEN 9 PRECEDING AND CURRENT ROW),
        'headshots', sum(headshots) OVER(ORDER BY date_key ROWS BETWEEN 9 PRECEDING AND CURRENT ROW),
        'damageDone', sum(damageDone) OVER(ORDER BY date_key ROWS BETWEEN 9 PRECEDING AND CURRENT ROW),
        'distanceTraveled', sum(distanceTraveled) OVER(ORDER BY date_key ROWS BETWEEN 9 PRECEDING AND CURRENT ROW),
        'kdRatio', avg(kdRatio) OVER(ORDER BY date_key ROWS BETWEEN 9 PRECEDING AND CURRENT ROW),
        'scorePerMinute', avg(scorePerMinute) OVER(ORDER BY date_key ROWS BETWEEN 9 PRECEDING AND CURRENT ROW),
        'monsters', sum(monsters) OVER(ORDER BY date_key ROWS BETWEEN 9 PRECEDING AND CURRENT ROW),
        'gooseeggs', sum(gooseeggs) OVER(ORDER BY date_key ROWS BETWEEN 9 PRECEDING AND CURRENT ROW)
      ),
      'smoothed_25', json_object(
        'matchesPlayed', count(matchesPlayed) OVER(ORDER BY date_key ROWS BETWEEN 24 PRECEDING AND CURRENT ROW),
        'kills', sum(kills) OVER(ORDER BY date_key ROWS BETWEEN 24 PRECEDING AND CURRENT ROW),
        'deaths', sum(deaths) OVER(ORDER BY date_key ROWS BETWEEN 24 PRECEDING AND CURRENT ROW),
        'gulagKills', sum(gulagKills) OVER(ORDER BY date_key ROWS BETWEEN 24 PRECEDING AND CURRENT ROW),
        'gulagDeaths', sum(gulagDeaths) OVER(ORDER BY date_key ROWS BETWEEN 24 PRECEDING AND CURRENT ROW),
        'headshots', sum(headshots) OVER(ORDER BY date_key ROWS BETWEEN 24 PRECEDING AND CURRENT ROW),
        'damageDone', sum(damageDone) OVER(ORDER BY date_key ROWS BETWEEN 24 PRECEDING AND CURRENT ROW),
        'distanceTraveled', sum(distanceTraveled) OVER(ORDER BY date_key ROWS BETWEEN 24 PRECEDING AND CURRENT ROW),
        'kdRatio', avg(kdRatio) OVER(ORDER BY date_key ROWS BETWEEN 24 PRECEDING AND CURRENT ROW),
        'scorePerMinute', avg(scorePerMinute) OVER(ORDER BY date_key ROWS BETWEEN 24 PRECEDING AND CURRENT ROW),
        'monsters', sum(monsters) OVER(ORDER BY date_key ROWS BETWEEN 24 PRECEDING AND CURRENT ROW),
        'gooseeggs', sum(gooseeggs) OVER(ORDER BY date_key ROWS BETWEEN 24 PRECEDING AND CURRENT ROW)
      ),
      'cumalative', json_object(
        'matchesPlayed', sum(matchesPlayed) OVER(ORDER BY date_key),
        'kills', sum(kills) OVER(ORDER BY date_key),
        'deaths', sum(deaths) OVER(ORDER BY date_key),
        'gulagKills', sum(gulagKills) OVER(ORDER BY date_key),
        'gulagDeaths', sum(gulagDeaths) OVER(ORDER BY date_key),
        'headshots', sum(headshots) OVER(ORDER BY date_key),
        'damageDone', sum(damageDone) OVER(ORDER BY date_key),
        'distanceTraveled', sum(distanceTraveled) OVER(ORDER BY date_key),
        'kdRatio', avg(kdRatio) OVER(ORDER BY date_key),
        'scorePerMinute', avg(scorePerMinute) OVER(ORDER BY date_key),
        'monsters', sum(monsters) OVER(ORDER BY date_key),
        'gooseeggs', sum(gooseeggs) OVER(ORDER BY date_key)
      )
    )
  ) as stats
  FROM
    vw_player_stats_by_game_wz
  WHERE
    player_id='${name}' AND
    date_key>='${start}' AND
    date_key<='${end}' AND
    1
  ORDER BY
    date_key
)

select json_group_array(stats) 'stats' from cte_stats
EOF
  )

  echo "${stats}" >"${outpath}"
}

write_player_stats_to_json() {
  local -n player_ids=$1

  local -r season_starts=($(
    sqlite3 "${dbfile}" <<-EOF
SELECT start FROM vw_seasons ORDER BY start
EOF
  ))

  local -r season_ends=($(
    sqlite3 "${dbfile}" <<-EOF
SELECT end FROM vw_seasons ORDER BY start
EOF
  ))

  local -r season_ids=($(
    sqlite3 "${dbfile}" <<-EOF
SELECT id FROM vw_seasons ORDER BY start
EOF
  ))

  for ((idx = 0; idx < ${#player_ids[@]}; ++idx)); do
    local name="${player_ids[idx]}"

    local start=$(get_ts)
    local outpath="${outdir_staging_data}/${name}_player_stats.json"
    write_player_rollup_stats_to_json "${name}" "${outpath}"
    local end=$(get_ts)
    report_file_written "${outpath}" "${start}" "${end}"

    for ((season_idx = 0; season_idx < ${#season_starts[@]}; ++season_idx)); do
      local season_start="${season_starts[season_idx]}"
      local season_end="${season_ends[season_idx]}"
      local season_id="${season_ids[season_idx]}"

      local start=$(get_ts)
      local outpath="${outdir_staging_data}/${name}_${season_id}_time_wz.json"
      write_player_time_stats_to_json "${name}" "${season_start}" "${season_end}" "${outpath}"
      local end=$(get_ts)
      report_file_written "${outpath}" "${start}" "${end}"

      local start=$(get_ts)
      local outpath="${outdir_staging_data}/${name}_${season_id}_game_wz.json"
      write_player_game_stats_to_json "${name}" "${season_start}" "${season_end}" "${outpath}"
      local end=$(get_ts)
      report_file_written "${outpath}" "${start}" "${end}"
    done

    local start=$(get_ts)
    local data_player_sessions=$(
      sqlite3 "${dbfile}" <<-EOF
SELECT json_object(
  'playerId', '${name}',
  'sessions', (
    SELECT
      json_group_array(
        json_object(
          'start', start,
          'end', end,
          'stats', json(stats)
        )
      )
    FROM vw_player_sessions_with_stats
    WHERE
      player_id='${name}' AND
      1
    ORDER BY start desc
  )
) res;
EOF
    )

    local outpath="${outdir_staging_data}/sessions_${name}.json"
    echo "${data_player_sessions}" >"${outpath}"
    local end=$(get_ts)
    report_file_written "${outpath}" "${start}" "${end}"


    local start=$(get_ts)
    local data_player_sessions_updated_at=$(
      sqlite3 "${dbfile}" <<-EOF
SELECT json_object(
  'updatedAt', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
  )
) res;
EOF
    )

    local outpath="${outdir_staging_data}/sessions_${name}_updated_at.json"
    echo "${data_player_sessions_updated_at}" >"${outpath}"
    local end=$(get_ts)
    report_file_written "${outpath}" "${start}" "${end}"

    echo
  done
}

function write_baked_assets() {
  cp -r index.html resources "${outdir_staging}"
}

function sync_files_to_dest() {
  rsync --verbose --checksum --progress --recursive --delete "${outdir_staging}"/ "${outdir_dest}"
  rm -rf "${outdir_staging}"
}

main() {
  local -r __ids=($(get_player_ids))

  write_baked_assets
  write_player_stats_to_json __ids
  write_leaderboards
  write_recent_matches
  write_recent_sessions
  write_meta

  sync_files_to_dest
}

main
