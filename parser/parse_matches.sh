#!/usr/bin/env bash

set -euo pipefail

readonly sourcedir="${COD_DATADIR}/fetcher/output"
readonly outdir="${COD_DATADIR}/parser/output"

readonly dbfile="${outdir}/data.sqlite"
readonly dbcommandsfile="${outdir}/_commands.sql"

readonly debug_out=false

die() {
  local -r msg="${1}"

  echo "ERROR: ${msg}"
  exit 1
}

### SQL

write_sql_start() {
  cat <<-EOF > "${dbcommandsfile}"
BEGIN TRANSACTION;

EOF
}

write_sql_end() {
  cat <<-EOF >> "${dbcommandsfile}"
COMMIT;
EOF
}

commit_sql() {
  sqlite3 "${dbfile}" <<-EOF
.read ${dbcommandsfile}
EOF
  rm "${dbcommandsfile}"
}

create_tables() {
  sqlite3 "${dbfile}" <<-EOF
CREATE TABLE IF NOT EXISTS players(
  player_uno_id TEXT PRIMARY KEY UNIQUE,
  player_id TEXT NOT NULL,
  is_core BOOLEAN NOT NULL DEFAULT 0 CHECK(is_core IN(0, 1))
);

CREATE TABLE IF NOT EXISTS raw_games(
  game_id TEXT NOT NULL,
  player_uno_id TEXT NOT NULL,
  stats BLOB,

  PRIMARY KEY (game_id, player_uno_id),
  FOREIGN KEY (player_uno_id)
    REFERENCES players (player_uno_id)
      ON DELETE CASCADE
      ON UPDATE NO ACTION
);

-- NOTE(jpr): this table exists mainly as a json parsing / normalization cache. ideally it would be a view, but when I
-- tested that out, performance was a lot worse (~100x slower). so I'm taking an in-between approach and dropping then
-- recreating the table on each runthrough.
DROP TABLE IF EXISTS wz_valid_games;
CREATE TABLE IF NOT EXISTS wz_valid_games(
  date_key TEXT NOT NULL,
  game_mode TEXT NOT NULL CHECK(game_mode IN ('mp', 'wz')),
  game_mode_sub TEXT NOT NULL,
  game_id TEXT NOT NULL,
  player_uno_id TEXT NOT NULL,
  numberOfPlayers INTEGER NOT NULL CHECK(numberOfPlayers > 0),
  numberOfTeams INTEGER NOT NULL CHECK(numberOfTeams > 0),

  score INTEGER NOT NULL,
  scorePerMinute REAL NOT NULL,
  kills INTEGER NOT NULL,
  deaths INTEGER NOT NULL,
  damageDone INTEGER NOT NULL,
  damageTaken INTEGER NOT NULL,
  gulagKills INTEGER NOT NULL,
  gulagDeaths INTEGER NOT NULL,
  teamPlacement INTEGER NOT NULL CHECK(teamPlacement > 0),
  kdRatio REAL NOT NULL,
  distanceTraveled REAL NOT NULL,
  headshots INTEGER NOT NULL,
  objectiveBrCacheOpen INTEGER NOT NULL,
  objectiveReviver INTEGER NOT NULL,
  objectiveBrDownAll INTEGER NOT NULL,
  objectiveDestroyedVehicleAll INTEGER NOT NULL,
  stats BLOB NOT NULL,

  PRIMARY KEY (game_id, player_uno_id),
  FOREIGN KEY (player_uno_id)
    REFERENCES players (player_uno_id)
      ON DELETE CASCADE
      ON UPDATE NO ACTION
);

DROP VIEW IF EXISTS vw_game_modes;
CREATE VIEW vw_game_modes AS
  SELECT * FROM (
    WITH cte_game_modes(
         id,                          mode, category,          display_name,             is_plunder, is_stimulus, wz_track_stats) AS (
      VALUES
        ('br_dmz_104',                'wz', 'wz_plunder',      'Blood Money',            true,  false, false),
        ('br_dmz_plnbld',             'wz', 'wz_plunder',      'Blood Money',            true,  false, false),
        ('br_dmz_85',                 'wz', 'wz_plunder',      'Plunder Duos',           true,  false, false),
        ('br_dmz_plndtrios',          'wz', 'wz_plunder',      'Plunder Trios',          true,  false, false),
        ('br_dmz_38',                 'wz', 'wz_plunder',      'Plunder Quads',          true,  false, false),
        ('br_dmz_76',                 'wz', 'wz_plunder',      'Plunder Quads',          true,  false, false),
        ('br_dmz_plunquad',           'wz', 'wz_plunder',      'Plunder Quads',          true,  false, false),

        ('br_71',                     'wz', 'wz_solo',         'Stim Solo',              false, true,  true),
        ('br_brbbsolo',               'wz', 'wz_solo',         'Stim Solo',              false, true,  true),
        ('br_brduostim_name2',        'wz', 'wz_duos',         'Stim Duos',              false, true,  true),
        ('br_brtriostim_name2',       'wz', 'wz_trios',        'Stim Trios',             false, true,  true),

        ('br_brsolo',                 'wz', 'wz_solo',         'Solo',                   false, false, true),
        ('br_87',                     'wz', 'wz_solo',         'Solo',                   false, false, true),
        ('br_brduos',                 'wz', 'wz_duos',         'Duos',                   false, false, true),
        ('br_88',                     'wz', 'wz_duos',         'Duos',                   false, false, true),
        ('br_brtrios',                'wz', 'wz_trios',        'Trios',                  false, false, true),
        ('br_25',                     'wz', 'wz_trios',        'Trios',                  false, false, true),
        ('br_74',                     'wz', 'wz_trios',        'Trios',                  false, false, true),
        ('br_brquads',                'wz', 'wz_quads',        'Quads',                  false, false, true),
        ('br_89',                     'wz', 'wz_quads',        'Quads',                  false, false, true),

        ('br_jugg_brtriojugr',        'wz', 'wz_jugtrios',     'Jugg Trios',             false, false, true),
        ('br_jugg_brquadjugr',        'wz', 'wz_jugquads',     'Jugg Quads',             false, false, true),
        ('br_mini_miniroyale',        'wz', 'wz_mini',         'Mini Royale',            false, false, true),
        ('br_brthquad',               'wz', 'wz_quads',        'Quads 200',              false, false, true),
        ('br_br_real',                'wz', 'wz_realism',      'Realism BR',             false, false, true),
        ('br_86',                     'wz', 'wz_realism',      'Realism BR',             false, false, true),

        ('br_77' ,                    'wz', 'wz_scopescatter', 'BR Scopes & Scattergun', false, false, false),
        ('brtdm_113',                 'wz', 'wz_rumble',       'Warzone Rumble',         false, false, false),
        ('br_kingslayer_kingsltrios', 'wz', 'wz_kingtrios',    'Kingslayer Trios',       false, false, false)
    )
    SELECT * from cte_game_modes
  )
;

DROP VIEW IF EXISTS vw_seasons;
CREATE VIEW vw_seasons AS
  SELECT * FROM (
    WITH cte_seasons(id, desc, start, end, sort_order) AS (
      VALUES
        ('lifetime', 'Lifetime', '1970-01-01T00:00:01Z', '2286-11-20T17:46:38Z', 1),
        ('season01', 'Season 1', '1970-01-01T00:00:01Z', '2020-02-11T17:59:59Z', 6),
        ('season02', 'Season 2', '2020-02-11T18:00:00Z', '2020-04-07T23:59:59Z', 5),
        ('season03', 'Season 3', '2020-04-08T00:00:00Z', '2020-06-11T02:59:59Z', 4),
        ('season04', 'Season 4', '2020-06-11T03:00:00Z', '2020-08-04T23:59:59Z', 3),
        ('season05', 'Season 5', '2020-08-05T00:00:00Z', '2286-11-20T17:46:38Z', 2)
    )
    SELECT * from cte_seasons
  )
;

DROP VIEW IF EXISTS vw_settings;
CREATE VIEW vw_settings AS
  SELECT * FROM (
    WITH cte_settings(id, desc, int_value) AS (
      VALUES
        ('monsters', 'Monster game threshold',
          8),
        ('session_delta_seconds', 'Amount of time between games for session detection',
          2 * 60 * 60 ) -- 2 hours
    )
    SELECT * from cte_settings
  )
;


DROP VIEW IF EXISTS vw_core_players;
CREATE VIEW vw_core_players AS
  SELECT DISTINCT player_id FROM players WHERE is_core=1;

DROP VIEW IF EXISTS vw_unknown_modes_wz;
CREATE VIEW vw_unknown_modes_wz AS
  SELECT DISTINCT json_extract(stats, '$.mode') mode
  FROM raw_games
  WHERE json_extract(stats, '$.gameType')='wz' AND mode NOT IN (SELECT id FROM vw_game_modes WHERE mode='wz');

DROP VIEW IF EXISTS vw_unknown_modes_mp;
CREATE VIEW vw_unknown_modes_mp AS
  SELECT DISTINCT json_extract(stats, '$.mode') mode
  FROM raw_games
  WHERE json_extract(stats, '$.gameType')='mp' AND mode NOT IN (SELECT id FROM vw_game_modes WHERE mode='mp');

DROP VIEW IF EXISTS vw_stats_wz;
CREATE VIEW vw_stats_wz AS
  SELECT
    gs.date_key,
    gs.game_mode_sub,
    gs.game_id,
    p.player_id AS player_id,
    gs.numberOfPlayers,
    gs.numberOfTeams,

    gs.score,
    gs.scorePerMinute,
    gs.kills,
    gs.deaths,
    gs.damageDone,
    gs.damageTaken,
    gs.gulagKills,
    gs.gulagDeaths,
    gs.teamPlacement,
    gs.kdRatio,
    gs.distanceTraveled,
    gs.headshots,
    gs.objectiveBrCacheOpen,
    gs.objectiveReviver,
    gs.objectiveBrDownAll,
    gs.objectiveDestroyedVehicleAll,

    json_object(
      'numberOfPlayers', gs.numberOfPlayers,
      'numberOfTeams', gs.numberOfTeams,
      'score', gs.score,
      'scorePerMinute', gs.scorePerMinute,
      'kills', gs.kills,
      'deaths', gs.deaths,
      'damageDone', gs.damageDone,
      'damageTaken', gs.damageTaken,
      'gulagKills', gs.gulagKills,
      'gulagDeaths', gs.gulagDeaths,
      'teamPlacement', gs.teamPlacement,
      'kdRatio', gs.kdRatio,
      'distanceTraveled', gs.distanceTraveled,
      'headshots', gs.headshots,
      'objectiveBrCacheOpen', gs.objectiveBrCacheOpen,
      'objectiveReviver', gs.objectiveReviver,
      'objectiveBrDownAll', gs.objectiveBrDownAll,
      'objectiveDestroyedVehicleAll', gs.objectiveDestroyedVehicleAll
    ) stats
  FROM
    wz_valid_games gs
  JOIN
    players p on p.player_uno_id=gs.player_uno_id
  WHERE
    gs.game_mode='wz' AND
    gs.game_mode_sub IN (select id from vw_game_modes where wz_track_stats=true) AND
    1
;

-- NOTE(jpr): disable MP until we figure out how we want to surface the data
-- DROP VIEW IF EXISTS vw_stats_mp;
-- CREATE VIEW vw_stats_mp AS
--   SELECT
--     gs.date_key,
--     gs.game_mode_sub,
--     gs.game_id,
--     p.player_id AS player_id,
--     gs.stats
--   FROM
--     valid_games gs
--   JOIN
--     players p on p.player_uno_id=gs.player_uno_id
--   WHERE
--     gs.game_mode='mp' AND
--     1
-- ;

DROP VIEW IF EXISTS vw_player_sessions;
CREATE VIEW vw_player_sessions AS
  WITH cte_deltas AS (
    SELECT
      date_key,
      player_id,
      cast(strftime('%s', date_key) as int) - lag(cast(strftime('%s', date_key) as int)) over (partition by player_id order by date_key) as delta
    FROM vw_stats_wz
    ORDER BY date_key
  ), cte_session_detections AS (
    SELECT
      vsw.date_key,
      cted.player_id,
        CASE
        WHEN ifnull(cted.delta, 9999999) >= (select int_value from vw_settings where id='session_delta_seconds') THEN
          1
        ELSE
          0
        END is_new_session
    FROM vw_stats_wz vsw
    JOIN cte_deltas cted on cted.date_key=vsw.date_key AND cted.player_id=vsw.player_id
    ORDER BY vsw.date_key
  ), cte_new_sessions AS(
    SELECT * from cte_session_detections where is_new_session=1 order by date_key
  ), cte_ordered_sessions AS(
    SELECT
      player_id,
      date_key start,
      strftime('%Y-%m-%dT%H:%M:%SZ', ifnull(lead(cast(strftime('%s', date_key) as int)) over (PARTITION by player_id order by date_key), 9999999999)  - 1, 'unixepoch') end
    FROM cte_new_sessions
  )

  SELECT
    player_id,
    ROW_NUMBER () OVER (PARTITION BY player_id ORDER BY start) session_number,
    player_id || '_' || ROW_NUMBER () OVER (PARTITION BY player_id ORDER BY start) session_id,
    start,
    end
  FROM cte_ordered_sessions
;

DROP VIEW IF EXISTS vw_player_sessions_with_stats;
CREATE VIEW vw_player_sessions_with_stats AS
  with cte_all_sessions AS (
    select vsw.*, vps.session_id, vps.session_number, vps.start, vps.end  from vw_stats_wz vsw join vw_player_sessions vps on
      vsw.date_key >= vps.start AND
      vsw.date_key < vps.end AND
      vsw.player_id = vps.player_id AND
      1
  )

  select player_id, session_id, session_number, start, end, json_object(
    'numGames', count(1),
    'kills', sum(kills),
    'deaths', sum(deaths),
    'damageDone', sum(damageDone),
    'maxKills', max(kills),
    'maxDamage', max(damageDone),
    'gulagKills', sum(gulagKills),
    'gulagDeaths', sum(gulagDeaths),
    'wins', sum(
      case
      when teamPlacement <= 1 then 1
      else 0
      end
    ),
    'top5', sum(
      case
      when teamPlacement <= 5 then 1
      else 0
      end
    ),
    'top10', sum(
      case
      when teamPlacement <= 10 then 1
      else 0
      end
    )
  ) stats from cte_all_sessions group by session_id order by player_id, start desc
;

DROP VIEW IF EXISTS vw_full_game_stats;
CREATE VIEW vw_full_game_stats AS
  WITH cte_recent_games AS (
    select date_key, game_id from vw_stats_wz where player_id in (SELECT * FROM vw_core_players) group by game_id
  )

  SELECT
    vsw.date_key,
    vsw.game_id,
    vsw.game_mode_sub,
    group_concat(vsw.player_id) player_ids,
    json_group_array(json_object('player_id', vsw.player_id, 'stats', json(vsw.stats))) player_stats
  FROM cte_recent_games crg
  JOIN vw_stats_wz vsw on vsw.game_id = crg.game_id
  GROUP BY crg.game_id
;

DROP VIEW IF EXISTS vw_team_stat_breakdowns;
CREATE VIEW vw_team_stat_breakdowns AS
  with cte_exploded AS (
    select
      date_key,
      player_ids,
      game_id,
      game_mode_sub,
      vgm.category,
      value
    from vw_full_game_stats, json_each(vw_full_game_stats.player_stats)
    join vw_game_modes vgm on vgm.id=game_mode_sub
    order by game_id
  ), cte_summarized AS (
    select date_key, game_id, game_mode_sub, category, player_ids,
      count(1) numPlayers,
      sum(json_extract(value, '$.stats.kills')) kills,
      sum(json_extract(value, '$.stats.damageDone')) dmg,
      sum(json_extract(value, '$.stats.deaths')) deaths,
      json_extract(value, '$.stats.teamPlacement') placement,
      json_extract(value, '$.stats.numberOfTeams') numberOfTeams
    from cte_exploded group by game_id order by date_key
  ), cte_only_full_teams AS (
    select * from cte_summarized where
      (category='wz_solo' AND numPlayers = 1) OR
      (category='wz_duos' AND numPlayers = 2) OR
      (category='wz_trios' AND numPlayers = 3) OR
      (category='wz_quads' AND numPlayers = 4) OR
      0
  ), cte_team_breakdowns AS (
    select
      category,
      player_ids,
      numPlayers,
      count(1) numGames,
      sum(
        case
        when placement=1 then 1
        else 0
        end
      ) numWins,
      sum(
        case
        when placement=numberOfTeams then 1
        else 0
        end
      ) numLastPlaces,
      round(avg(kills), 2) avgKills,
      round(avg(dmg), 2) avgDmg,
      round(avg(deaths), 2) avgDeaths,
      round(avg(placement), 2) avgPlacement,
      max(kills) maxKills,
      max(dmg) maxDmg,
      max(deaths) maxDeaths
    from cte_only_full_teams
    group by category, player_ids
  )

  select
    category, player_ids, numGames, numWins, numLastPlaces, avgKills, avgDmg, avgDeaths, avgPlacement, maxKills, maxDmg, maxDeaths,
    json_object(
      'player_ids', player_ids,
      'numGames', numGames,
      'numWins', numWins,
      'numLastPlaces', numLastPlaces,
      'avgKills', avgKills,
      'avgDmg', avgDmg,
      'avgDeaths', avgDeaths,
      'avgPlacement', avgPlacement,
      'maxKills', maxKills,
      'maxDmg', maxDmg,
      'maxDeaths', maxDeaths
    ) jsonStats
  FROM cte_team_breakdowns where numGames > 1
;

DROP VIEW IF EXISTS vw_player_stats_by_day_wz;
CREATE VIEW vw_player_stats_by_day_wz AS
  SELECT
  date(date_key) 'date_key',
  player_id,
  count(1) 'matchesPlayed',
  sum(kills) 'kills',
  sum(deaths) 'deaths',
  sum(gulagKills) 'gulagKills',
  sum(gulagDeaths) 'gulagDeaths',
  sum(headshots) 'headshots',
  sum(damageDone) 'damageDone',
  sum(distanceTraveled) 'distanceTraveled',
  avg(kdRatio) 'kdRatio',
  avg(scorePerMinute) 'scorePerMinute',
  sum(
    case
    when kills >= (select int_value from vw_settings where id='monsters') then 1
    else 0
    end
  ) 'monsters',
  sum(
    case
    when kills = 0 then 1
    else 0
    end
  ) 'gooseeggs'
  FROM
    vw_stats_wz
  GROUP BY
    player_id, date(date_key)
  ORDER BY
    date_key
;

-- NOTE(jpr): this isnt really needed but it helps to keep the logic in one place alongside the 'stats_by_day' version
DROP VIEW IF EXISTS vw_player_stats_by_game_wz;
CREATE VIEW vw_player_stats_by_game_wz AS
  SELECT
    date_key 'date_key',
    player_id,
    1 'matchesPlayed',
    ifnull(vgm.display_name, 'Unknown &lt;' || game_mode_sub || '&gt;') 'mode',
    numberOfPlayers,
    numberOfTeams,
    teamPlacement,
    kills,
    deaths,
    gulagKills,
    gulagDeaths,
    headshots,
    damageDone,
    distanceTraveled,
    kdRatio,
    scorePerMinute,
    case
      WHEN kills >= (select int_value from vw_settings where id='monsters') then 1
      ELSE 0
      END 'monsters',
    case
      WHEN kills = 0 then 1
      ELSE 0
      END 'gooseeggs'
  FROM
    vw_stats_wz
  LEFT JOIN
    vw_game_modes vgm ON vgm.id=game_mode_sub
  ORDER BY
    date_key
;
-- migrations
EOF
}

seed_data() {
  local -r players=$( cat ../config/players.json  | jq -r ". | map({name: .name, unoId: (.accounts[].unoId)}) | unique | map( \"('\" + (.name | ascii_downcase) + \"', '\" + .unoId + \"')\") | join(\", \")" )
  local -r core_players=$( cat ../config/players.json  | jq -r "[.[] | select(.isCore)] | map( \"'\" + (.name | ascii_downcase) + \"'\") | join(\", \")" )

  sqlite3 "${dbfile}" <<-EOF
INSERT OR IGNORE INTO players(player_id, player_uno_id) VALUES
  ${players};

UPDATE players SET
  is_core =
    CASE
      WHEN player_id IN (${core_players}) THEN 1
      ELSE 0
    END;
EOF
}

get_player_ids() {
  sqlite3 "${dbfile}" <<-EOF
SELECT player_id FROM players ORDER BY player_id;

EOF
}

get_player_uno_ids() {
  sqlite3 "${dbfile}" <<-EOF
SELECT player_uno_id FROM players ORDER BY player_id;

EOF
}

get_unwritten() {
  local -r source="${1}"
  local -r files=$( ls "${source}"/ | grep -Eo 'match_[0-9]+_[0-9]+' | sed 's/match_//g' | awk "{ print \"  ('\" \$0 \"'),\"; }" )

  sqlite3 "${dbfile}" <<-EOF
WITH cte_lookup(id) AS (
VALUES
${files}
  ('xnullx')
)
SELECT id FROM cte_lookup WHERE id NOT IN (
  SELECT game_id || '_' || player_uno_id FROM raw_games
  UNION SELECT 'xnullx'
);

EOF
}

initialize_db() {
  mkdir -p "${outdir}"

  create_tables
  seed_data
}

insert_stats_raw() {
  local -r player_key="${1}"
  local -r game_id="${2}"
  local -r data="$(echo "${3}" | sed "s/'/''/g")"

  ($debug_out && echo "[${game_id}] [${player_key}]") || true

  cat <<-EOF >> "${dbcommandsfile}"
INSERT OR IGNORE INTO raw_games(game_id, player_uno_id, stats) VALUES
  ('${game_id}', '${player_key}', '${data}');

EOF
}

backfill_match_data() {
  cat <<-EOF >> "${dbcommandsfile}"
INSERT OR IGNORE INTO wz_valid_games SELECT
  strftime('%Y-%m-%dT%H:%M:%SZ', json_extract(stats, '$.utcEndSeconds'), 'unixepoch') AS date_key,
  json_extract(stats, '$.gameType') AS game_mode,
  json_extract(stats, '$.mode') AS game_mode_sub,
  game_id,
  player_uno_id,
  ifnull(json_extract(stats, '$.playerCount'), -1) AS numberOfPlayers,
  ifnull(json_extract(stats, '$.teamCount'), -1) AS numberOfTeams,

  ifnull(json_extract(stats, '$.playerStats.score'), 0) AS score,
  ifnull(json_extract(stats, '$.playerStats.scorePerMinute'), 0) AS scorePerMinute,
  ifnull(json_extract(stats, '$.playerStats.kills'), 0) AS kills,
  ifnull(json_extract(stats, '$.playerStats.deaths'), 0) AS deaths,
  ifnull(json_extract(stats, '$.playerStats.damageDone'), 0) AS damageDone,
  ifnull(json_extract(stats, '$.playerStats.damageTaken'), 0) AS damageTaken,
  CASE
    -- NOTE(jpr): stimulus modes report each buyback as a gulagDeath
    WHEN json_extract(stats, '$.mode') IN (SELECT id FROM vw_game_modes WHERE is_stimulus=true) THEN 0
    WHEN ifnull(json_extract(stats, '$.playerStats.gulagKills'), 0) >= 1 THEN 1
    ELSE 0
    END AS gulagKills,
  CASE
    -- NOTE(jpr): stimulus modes report each buyback as a gulagDeath
    WHEN json_extract(stats, '$.mode') IN (SELECT id FROM vw_game_modes WHERE is_stimulus=true) THEN 0
    -- NOTE(jpr): it appears gulagDeaths is reported incorrectly if you die multiple times in a match. gulagWins seems
    -- to be correct, so lets defer to that.
    WHEN ifnull(json_extract(stats, '$.playerStats.gulagKills'), 0) >= 1 THEN 0
    WHEN ifnull(json_extract(stats, '$.playerStats.gulagDeaths'), 0) >= 1 THEN 1
    ELSE 0
    END AS gulagDeaths,
  ifnull(json_extract(stats, '$.playerStats.teamPlacement'), -1) AS teamPlacement,
  ifnull(json_extract(stats, '$.playerStats.kdRatio'), 0) AS kdRatio,
  ifnull(json_extract(stats, '$.playerStats.distanceTraveled'), 0) AS distanceTraveled,
  ifnull(json_extract(stats, '$.playerStats.headshots'), 0) AS headshots,
  ifnull(json_extract(stats, '$.playerStats.objectiveBrCacheOpen'), 0) AS objectiveBrCacheOpen,
  ifnull(json_extract(stats, '$.playerStats.objectiveReviver'), 0) AS objectiveReviver,
  ifnull(json_extract(stats, '$.playerStats.objectiveBrDownEnemyCircle1'), 0) +
    ifnull(json_extract(stats, '$.playerStats.objectiveBrDownEnemyCircle2'), 0) +
    ifnull(json_extract(stats, '$.playerStats.objectiveBrDownEnemyCircle3'), 0) +
    ifnull(json_extract(stats, '$.playerStats.objectiveBrDownEnemyCircle4'), 0) +
    ifnull(json_extract(stats, '$.playerStats.objectiveBrDownEnemyCircle5'), 0) +
    ifnull(json_extract(stats, '$.playerStats.objectiveBrDownEnemyCircle6'), 0) +
    0
    AS objectiveBrDownAll,
  ifnull(json_extract(stats, '$.playerStats.objectiveDestroyedVehicleLight'), 0) +
    ifnull(json_extract(stats, '$.playerStats.objectiveDestroyedVehicleMedium'), 0) +
    ifnull(json_extract(stats, '$.playerStats.objectiveDestroyedVehicleHeavy'), 0) +
    0
    AS objectiveDestroyedVehicleAll,
  json_extract(stats, '$.playerStats') AS stats
FROM
  raw_games
WHERE
  player_uno_id IN (SELECT player_uno_id FROM players) AND
  game_id || '_' || player_uno_id NOT IN (select game_id || '_' || player_uno_id FROM wz_valid_games) AND

  -- filter out buggy stats. seems to be a lot from early on in API, not so much lately
  NOT (json_extract(stats, '$.playerStats.damageDone') is null) AND
  NOT (json_extract(stats, '$.playerStats.damageTaken') is null) AND
  NOT (deaths = 0 AND damageTaken = 0) AND

  -- TODO(jpr): think about filtering out early leaves / DCs. this is mostly handled
  -- by the (deaths=0 and damageTaken=0) above, but there are still some obvious DCs
  -- which may or may not want to be included

  1
;

EOF
}

###

get_ts() {
  echo $( gdate +%s%N | cut -b1-13 )
}

ingest_successes() {
  local -r source="${1}"
  local -n player_names=$2
  local -n player_uno_ids=$3

  [ -d "${source}" ] || die "no dir at [${source}]"

  local other=0
  local player=

  local unwritten=($( get_unwritten "${source}" ))
  echo "Writing [${#unwritten[@]}] new results"

  for ((idx=0; idx<${#unwritten[@]}; ++idx)); do
    local rawname="${unwritten[idx]}"
    local match_id="$(echo "${rawname}" | awk -F'_' '{print $1;}')"
    local match_unoid="$(echo "${rawname}" | awk -F'_' '{print $2;}')"
    local file="${source}/match_${match_id}_${match_unoid}.json"
    local data=$(cat "${file}")

    insert_stats_raw "${match_unoid}" "${match_id}" "${data}"
  done
}

main() {
  initialize_db
  local -r __ids=($( get_player_ids ))
  local -r __uno_ids=($( get_player_uno_ids ))

  write_sql_start

  ingest_successes "${sourcedir}" __ids __uno_ids
  backfill_match_data

  write_sql_end
  commit_sql
}

main
