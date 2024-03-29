(() => {
  const deepFetch = (obj, keyPath) => {
    for (let idx = 0; idx < keyPath.length; idx++) {
      const key = keyPath[idx];
      obj = obj[key];
      if (!obj) {
        break;
      }
    }
    return obj;
  };

  const roundTo2 = (number) => {
    return Math.round(100 * number) / 100;
  };

  const ONE_DAY = 24 * 3600 * 1000;
  const splitKey = '--';
  const statDropdownOptions = [
    {
      dataBucket: 'days',
      dropdownValue: 'kdratio', dropdownText: 'Raw K/D', chartTitle: 'Raw K/D',
      statResolver: (data) => {
        const kills = deepFetch(data, ['cumalative', 'kills']);
        const deaths = deepFetch(data, ['cumalative', 'deaths']);
        if (kills == null && deaths == null) return null;
        if ((kills || 0) + (deaths || 0) == 0) return 0;
        return (kills || 0) / ((deaths || 0) == 0 ? 1 : deaths);
      },
    },
    {
      dataBucket: 'days',
      dropdownValue: 'recentkddays', dropdownText: 'Smoothed K/D (days)', chartTitle: 'Smoothed K/D (past 7 days)',
      statResolver: (data) => {
        const kills = deepFetch(data, ['smoothed_7', 'kills']);
        const deaths = deepFetch(data, ['smoothed_7', 'deaths']);
        if (kills == null && deaths == null) return null;
        if ((kills || 0) + (deaths || 0) == 0) return 0;
        return (kills || 0) / ((deaths || 0) == 0 ? 1 : deaths);
      }
    },
    {
      dataBucket: 'games',
      dropdownValue: 'recentkdgames', dropdownText: 'Smoothed K/D (games)', chartTitle: 'Smoothed K/D (past 25 games)',
      statResolver: (data) => {
        const kills = deepFetch(data, ['smoothed_25', 'kills']);
        const deaths = deepFetch(data, ['smoothed_25', 'deaths']);
        if (kills == null && deaths == null) return null;
        if ((kills || 0) + (deaths || 0) == 0) return 0;
        return (kills || 0) / ((deaths || 0) == 0 ? 1 : deaths);
      }
    },
    {
      dataBucket: 'days',
      dropdownValue: 'killspergame', dropdownText: 'Kills / Game', chartTitle: 'Kills Per Game',
      statResolver: (data) => {
        const kills = deepFetch(data, ['cumalative', 'kills']);
        const matches = deepFetch(data, ['cumalative', 'matchesPlayed']);
        if (kills == null && matches == null) return null;
        if ((matches || 0) == 0) return 0;
        return (kills || 0.0) / (matches || 0.0);
      }
    },
    {
      dataBucket: 'days',
      dropdownValue: 'deathspergame', dropdownText: 'Deaths / Game', chartTitle: 'Deaths Per Game',
      statResolver: (data) => {
        const deaths = deepFetch(data, ['cumalative', 'deaths']);
        const matches = deepFetch(data, ['cumalative', 'matchesPlayed']);
        if (deaths == null && matches == null) return null;
        if ((matches || 0) == 0) return 0;
        return (deaths || 0.0) / (matches || 0.0);
      }
    },
    {
      dataBucket: 'days',
      dropdownValue: 'scorepermin', dropdownText: 'Score / Minute', chartTitle: 'Score Per Min',
      statPath: ['raw', 'scorePerMinute'].join(splitKey)
    },
    {
      dataBucket: 'days',
      dropdownValue: 'gulagwinpercent', dropdownText: 'Gulag Win %', chartTitle: 'Gulag Win %',
      statResolver: (data) => {
        const wins = deepFetch(data, ['cumalative', 'gulagKills']);
        const losses = deepFetch(data, ['cumalative', 'gulagDeaths']);
        if (wins == null && losses == null) return null;
        if ((wins || 0) + (losses || 0) == 0) return 0;
        return 100.0 * (wins || 0.0) / ((wins || 0.0) + (losses || 0.0));
      },
    },
    {
      dataBucket: 'days',
      dropdownValue: 'dmgpergame', dropdownText: 'Damage / Game', chartTitle: 'Damage Per Game',
      statResolver: (data) => {
        const dmg = deepFetch(data, ['cumalative', 'damageDone']);
        const matches = deepFetch(data, ['cumalative', 'matchesPlayed']);
        if (dmg == null && matches == null) return null;
        if ((matches || 0) == 0) return 0;
        return (dmg || 0.0) / (matches || 0.0);
      },
    },
    {
      dataBucket: 'days',
      dropdownValue: 'dmgperkill', dropdownText: 'Damage / Kill', chartTitle: 'Damage Per Kill',
      statResolver: (data) => {
        const dmg = deepFetch(data, ['cumalative', 'damageDone']);
        const kills = deepFetch(data, ['cumalative', 'kills']);
        if (dmg == null && kills == null) return null;
        if ((kills || 0) == 0) return 0;
        return (dmg || 0.0) / (kills || 0.0);
      },
    },
    {
      dataBucket: 'days',
      dropdownValue: 'monsterpercent', dropdownText: 'Monster Game %', chartTitle: 'Monster Game %',
      statResolver: (data) => {
        const monsters = deepFetch(data, ['cumalative', 'monsters']);
        const matches = deepFetch(data, ['cumalative', 'matchesPlayed']);
        if (monsters == null && matches == null) return null;
        if ((matches || 0) == 0) return 0;
        return 100.0 * (monsters || 0.0) / (matches || 0.0);
      },
    },
    {
      dataBucket: 'days',
      dropdownValue: 'gooseeggpercent', dropdownText: 'Goose Egg %', chartTitle: 'Goose Egg %',
      statResolver: (data) => {
        const gooseeggs = deepFetch(data, ['cumalative', 'gooseeggs']);
        const matches = deepFetch(data, ['cumalative', 'matchesPlayed']);
        if (gooseeggs == null && matches == null) return null;
        if ((matches || 0) == 0) return 0;
        return 100.0 * (gooseeggs || 0.0) / (matches || 0.0);
      },
    },
  ];

  let _chart = null;
  let _queryParams = null;

  let _playerNames = [];
  let _corePlayerNames = [];
  let _seasonsInfo = null;
  let _metaInfo = null

  const loadInitialData = async () => {
    const data = await Promise.all([
      fetch("/data/output/players.json").then(it => it.text()),
      fetch("/data/output/meta.json").then(it => it.text()),
      fetch("/data/output/seasons.json").then(it => it.text()),
    ]);
    _playerNames = JSON.parse(data[0]);
    _corePlayerNames = _playerNames.filter(it => it.isCore).map(it => it.name);
    _metaInfo = JSON.parse(data[1]);
    _seasonsInfo = JSON.parse(data[2]);
  };

  const hideEmptyModeMessage = () => {
    document.querySelector('#empty-mode-message').style.display = 'none';
  };
  const setEmptyMessage = (msg) => {
    const el = document.querySelector('#empty-mode-message');
    el.innerHTML = msg;
    el.style.display = 'absolute';
  };

  const fetchDataByTime = async (name, seasonid) => {
    const path = `/data/output/${name.toLowerCase()}_${seasonid}_time_wz.json`;
    return _fetchAndParseData(path);
  };
  const fetchDataByGame = async (name, seasonid) => {
    const path = `/data/output/${name.toLowerCase()}_${seasonid}_game_wz.json`;
    return _fetchAndParseData(path);
  };

  const _fetchAndParseData = async (path) => {
    const data = await fetch(path).then(it => it.text()).then(it => JSON.parse(it));

    return data.sort((a, b) => {
      return a.date.localeCompare(b.date);
    }).filter(it => it.stats != null).map(it => {
      const dt = new Date(it.date);
      const stats = it.stats;
      return { dt, stats };
    });
  };

  const setSeriesByBakedStat = async (statName, timeframe) => {
    const config = statDropdownOptions.find(it => it.dropdownValue == statName);
    if (config == null || (config.statPath == null && config.statResolver == null)) {
      setEmptyMessage(`No data found for [${statName}]`);
      return;
    }

    if (config.statPath) {
      await setSeriesByStat(config.statPath, config.dataBucket, timeframe);
    } else {
      await _setSeriesByCustomStat(config.statResolver, config.dataBucket, timeframe);
    }
    _chart.setTitle({ text: `Comparing ${_seasonsInfo.seasons.find(it => it.id == timeframe).desc}<br />[${config.chartTitle}]` }, null, false);
    _chart.redraw(false);
    _chart.reflow();
  };

  const setSeriesByStat = async (statName, dataBucket, timeframe) => {
    const resolveStat = (graph, keys) => {
      const res = graph[keys[0]];
      if (!res) {
        return null;
      }
      if (keys.length == 1) {
        return res
      }
      return resolveStat(res, keys.slice(1));
    };

    const statKeyPath = statName.split(splitKey);
    await _setSeriesByCustomStat(it => resolveStat(it, statKeyPath), dataBucket, timeframe);

    _chart.setTitle({ text: `Comparing<br />[${statName}]` }, null, false);
    _chart.redraw(false);
    _chart.reflow();
  };

  const fetchData = (playerName, dataBucket, timeframe) => {
    if (dataBucket === 'days') {
      return fetchDataByTime(playerName, timeframe);
    } else if (dataBucket === 'games') {
      return fetchDataByGame(playerName, timeframe);
    } else {
      return Promise.error(`unknown databucket [${dataBucket}]`);
    }
  }

  const _setSeriesByCustomStat = async (mappingFn, dataBucket, timeframe) => {
    setEmptyMessage('Loading...');
    const dataByUser = await Promise.all(
      _playerNames.map(it => fetchData(it.name, dataBucket, timeframe))
    );
    hideEmptyModeMessage();

    const visibleNames = _queryParams.get('names') ? _queryParams.get('names').split(splitKey) : _corePlayerNames;

    dataByUser.map((data, idx) => {
      let d = dataBucket == 'days' ? data.map(it => { return { x: (new Date(it.dt)).getTime(), y: mappingFn(it.stats) }; }) : data.map((it, idx) => { return { x: idx - data.length + 1, y: mappingFn(it.stats) }; });
      d = d.map(it => [it.x, it.y]);
      _chart.addSeries({
        name: _playerNames[idx].name,
        visible: visibleNames.includes(_playerNames[idx].name),
        data: d,
      }, false, false);
    });
    configureChart(dataBucket, timeframe);
  };

  const configureChart = (dataBucket, timeframe) => {
    if (dataBucket == 'games') {
      _chart.xAxis[0].update({
        type: 'spline',
        min: -30,
        labels: { enabled: false },
      }, true);
    } else {
      const season = _seasonsInfo.seasons.find(it => it.id == timeframe);
      const endDate = new Date(season.end) > new Date() ? new Date() : new Date(season.end);
      _chart.xAxis[0].update({
        type: 'datetime',
        min: endDate - (30 * ONE_DAY),
        tickInterval: ONE_DAY * 7,
        labels: {
          formatter: function () {
            const dt = new Date(this.value).toLocaleDateString('en-US', { month: "short", day: "numeric" });
            return `<text><tspan>${dt}</tspan></text>`;
          },
          step: 1,
          rotation: -45,
        },
      }, true);
    }
  };

  const buildChart = () => {
    return Highcharts.chart('container', {
      chart: {
        type: "spline",
        height: 400,
        panning: true,
        panKey: 'shift',
        zoomType: 'x',
        // displayErrors: true,
      },
      title: {
        text: null,
      },
      legend: {
        align: "center",
        verticalAlign: "bottom",
        layout: "horizontal",
        itemStyle: {
          color: Highcharts.getOptions().colors[0],
          fontSize: "0.925rem"
        },
        itemHoverStyle: {
          color: Highcharts.getOptions().colors[0],
        }
      },
      tooltip: {
        crosshairs: !0,
        formatter: function (tooltip) {
          const val = Highcharts.numberFormat(this.y, 2);
          if (_chart.xAxis[0].type == 'datetime') {
            const dt = new Date(this.x).toLocaleDateString('en-US', { month: "short", day: "numeric" });
            return `<span style="font-size: 10px">${dt}</span><br /><strong>${this.point.series.name}:</strong> ${val}`;
          } else {
            return `<strong>${this.point.series.name}:</strong> ${val}`;
          }
        },
      },
      plotOptions: {
        series: {
          lineWidth: 3.5,
          marker: {
            enabled: !1
          },
          events: {
            legendItemClick: function (e) {
              setTimeout(() => {
                const url = new URL(window.location);
                const params = url.searchParams;
                const visibleSeries = _chart.series.filter(it => it.visible);
                if (visibleSeries.length == 0 || visibleSeries.length == _playerNames.length) {
                  params.delete('names');
                } else {
                  const joined = visibleSeries.map(it => it.name).join(splitKey);
                  params.set('names', joined);
                }
                history.replaceState(null, '', url);
                _queryParams = params;
              }, 10);
            },
          },
        },
      },
      time: {
        useUTC: !1
      },
      xAxis: {
        title: { text: null, },
        scrollbar: { enabled: true },
      },
      yAxis: {
        title: {
          text: null,
        },
      },
    });
  };

  const configureStatDropdown = () => {
    const dropdown = document.querySelector('.stat-dropdown');

    let option = document.createElement('option');
    statDropdownOptions.forEach(config => {
      option = document.createElement('option');
      option.value = config.dropdownValue;
      option.innerHTML = config.dropdownText;
      option.selected = _queryParams.get('stat') == config.dropdownValue;
      dropdown.appendChild(option);
    });

    return dropdown;
  };

  const configureSeasonDropdown = () => {
    const dropdown = document.querySelector('.season-dropdown');

    let option = document.createElement('option');
    _seasonsInfo.seasons.forEach(config => {
      option = document.createElement('option');
      option.value = config.id;
      option.innerHTML = config.id == _seasonsInfo.current ? config.desc + ' (current)' : config.desc;
      option.selected = _queryParams.get('timeframe') == config.id;
      dropdown.appendChild(option);
    });

    return dropdown;
  };

  const populateRecordsTable = async (selector, filename) => {
    const container = document.querySelector(selector);
    const path = `/data/output/${filename}.json`;
    const data = await fetch(path).then(it => it.text()).then(it => JSON.parse(it));

    const cardWithConfig = (title, value, dateText, playerName) => {
      const imgPart = playerName == null ? '' : `<img class="card--player-img" src="resources/images/players/${playerName.toLowerCase()}.jpg">`;
      const html = `
<div class="card--title">${title}</div>
<div class="card--value">${value}</div>
<div class="card--attribution card-deemphasize">${imgPart}<span class="card--date-text">${dateText}</span></div>
    `;

      const card = document.createElement('div');
      card.className = 'card';
      card.innerHTML = html;

      return card;
    };

    data.forEach(rowData => {
      const records = [];
      const addedNames = new Set();
      let bestValue = null;
      rowData.meta.forEach(meta => {
        if ((bestValue == null || meta.value == bestValue) && !addedNames.has(meta.player_id)) {
          records.push(meta);
          addedNames.add(meta.player_id);
          bestValue = meta.value;
        }
      });
      if (records.length == 1) {
        const meta = records[0];
        let dateText = '';

        const isSameDay = (dt1, dt2) => {
          const config = { year: 'numeric', month: 'short', day: 'numeric' };
          const d1 = new Date(dt1).toLocaleString('en-US', config);
          const d2 = new Date(dt2).toLocaleString('en-US', config);
          return d1 === d2;
        };

        if (meta.date_key != null) {
          const config = { month: 'short', day: 'numeric' };
          const dt = new Date(meta.date_key).toLocaleDateString('en-US', config);
          if (meta.until_date_key == null || isSameDay(meta.date_key, meta.until_date_key)) {
            dateText = ` (${dt})`;
          } else {
            const untilDt = new Date(meta.until_date_key).toLocaleDateString('en-US', config);
            dateText = ` (${dt} - ${untilDt})`;
          }
        }

        let card = cardWithConfig(rowData.title, meta.value, meta.player_id + dateText, meta.player_id);
        container.appendChild(card);
      } else {
        const names = Array.from(addedNames).sort((a, b) => a.localeCompare(b)).join(' / ');
        let card = cardWithConfig(rowData.title, records[0].value, names);
        container.appendChild(card);
      }
    });
  };

  const populateGameRecordsTable = () => populateRecordsTable('.records-bygame-table-container .records', 'leaderboard_bygame');
  const populateLifetimeRecordsTable = () => populateRecordsTable('.records-lifetime-table-container .records', 'leaderboard_lifetime');

  const populateTeamRecordsTable = async () => {
    const container = document.querySelector('.teamrecords');
    const path = '/data/output/team_leaderboards.json';
    const data = await fetch(path).then(it => it.text()).then(it => JSON.parse(it)).then(it => it.sort((a, b) => a.sortOrder - b.sortOrder));

    const cardWithConfig = (mode, teamStats) => {
      let html = `
<div class="card--title">${mode}</div>
<table class="sortable-table sort-inverted">
<thead>
<tr>
  <th data-sort-method='none'>Team</th>
  <th data-sort-method='number' aria-sort='descending' data-sort-default>Avg<br />Place</th>
  <th data-sort-method='number'>Avg<br />Kills</th>
  <th data-sort-method='number'>Avg<br />Dmg</th>
  <th data-sort-method='number'>Max<br />Kills</th>
  <th data-sort-method='number'>Max<br />Dmg</th>
  <th data-sort-method='number'>Max<br />Deaths</th>
  <th data-sort-method='number'>Games</th>
  <th data-sort-method='number'>Wins</th>
</tr>
</thead>
<tbody>
`

      teamStats.forEach(it => {
        html += `
<tr>
  <td class="text-capitalize">${it.player_ids.split(',').join('&nbsp;/&nbsp;')}</td>
  <td>${it.avgPlacement}</td>
  <td>${it.avgKills}</td>
  <td>${it.avgDmg}</td>
  <td>${it.maxKills}</td>
  <td>${it.maxDmg}</td>
  <td>${it.maxDeaths}</td>
  <td>${it.numGames}</td>
  <td>${it.numWins}</td>
</tr>
`;
      });
      html += `
</tbody>
</table>
`;

      const card = document.createElement('div');
      card.className = 'card';
      card.innerHTML = html;

      const el = card.querySelector('.sortable-table');
      new Tablesort(el, {
        descending: true
      });

      return card;
    };

    data.forEach(rowData => {
      const first = rowData.stats[0];
      let card = cardWithConfig(rowData.mode, rowData.stats);
      container.appendChild(card);
    });
  };

  const populateRecentMatches = async () => {
    const container = document.querySelector('.matches');
    const path = '/data/output/recent_matches.json';
    const data = await fetch(path).then(it => it.text()).then(it => JSON.parse(it));

    const cardWithConfig = (dateText, modeText, playerText, placementText, numTeams, numKills, numDamage) => {
      const isWin = placementText == 1;
      placementText = placementText.toString();
      switch (placementText) {
        case '11':
        case '12':
        case '13':
          placementText = `${placementText}th`;
          break;
        default:
          switch (placementText[placementText.length - 1]) {
            case '1':
              placementText = `${placementText}st`;
              break;
            case '2':
              placementText = `${placementText}nd`;
              break;
            case '3':
              placementText = `${placementText}rd`;
              break;
            default:
              placementText = `${placementText}th`;
              break;
          }
          break;
      }
      const html = `
<p class="card--date card-deemphasize">${dateText}</p>
<p class="card--match-type card-deemphasize">${modeText}</p>
<div class="card--placement">${placementText}<span class="card-deemphasize" style="font-size: 0.6em"> / ${numTeams}</span></div>
<p class="card--player-names">${playerText}</p>
<div class="card--stats-container card-deemphasize">
<div class="card--stats-stat">
<p class="card--stats-stat-value">${numKills}</p>
<p class="card--stats-stat-name">${numKills == 1 ? 'Kill' : 'Kills'}</p>
</div>
<div class="card--stats-stat">
<p class="card--stats-stat-value">${numDamage}</p>
<p class="card--stats-stat-name">Damage</p>
</div>
</div>
`;

      const card = document.createElement('div');
      card.className = isWin ? 'card card-winner' : 'card';
      card.innerHTML = html;

      return card;
    };

    data.forEach(rowData => {
      const dt = new Date(rowData.date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: 'numeric' });
      const placement = rowData.player_stats[0].stats.teamPlacement;
      const numTeams = rowData.player_stats[0].stats.numberOfTeams;
      const kills = rowData.player_stats.reduce((memo, item) => {
        return memo + item.stats.kills;
      }, 0);
      const dmg = rowData.player_stats.reduce((memo, item) => {
        return memo + item.stats.damageDone;
      }, 0);

      const card = cardWithConfig(dt, rowData.game_mode, rowData.player_ids.split(',').join(' / '), placement, numTeams, kills, dmg);
      container.appendChild(card);
    });
  };

  const populateRecentSessions = async () => {
    const container = document.querySelector('.sessions');
    const path = '/data/output/recent_sessions.json';
    const data = await fetch(path).then(it => it.text()).then(it => JSON.parse(it));

    const cardWithConfig = (playerText, numGames, numWins, top5s, top10s, gulagWins, gulagLosses, numKills, numDeaths, damageDone, maxKills, maxDamage) => {
      const kdText = roundTo2(numDeaths == 0 ? numKills : numKills / numDeaths);
      const html = `
<div style="display: flex; justify-content: space-between; align-items: center; text-align: center; line-height: 1.2">
<p class="card--player-text"><a href="/resources/pages/player.html?player=${playerText}">${playerText}</a></p>
<p class="card--games-text card-deemphasize">${numGames} ${numGames == 1 ? 'Game' : 'Games'}</p>
</div>
<div class="card--stats-container">
<div class="card--stats-stat">
<p class="card--stats-stat-value">${numWins}</p>
<p class="card--stats-stat-name">${numWins == 1 ? 'Win' : 'Wins'}</p>
</div>
<div class="card--stats-stat">
<p class="card--stats-stat-value">${top5s}</p>
<p class="card--stats-stat-name">${top5s == 1 ? 'Top 5' : 'Top 5s'}</p>
</div>
<div class="card--stats-stat">
<p class="card--stats-stat-value">${top10s}</p>
<p class="card--stats-stat-name">${top10s == 1 ? 'Top 10' : 'Top 10s'}</p>
</div>
</div>
<div class="card--stats-container">
<div class="card--stats-stat">
<p class="card--stats-stat-value">${roundTo2(numKills / numGames)} / ${maxKills}</p>
<p class="card--stats-stat-name">Kills (avg/best)</p>
</div>
<div class="card--stats-stat">
<p class="card--stats-stat-value">${Math.trunc(damageDone / numGames)} / ${maxDamage}</p>
<p class="card--stats-stat-name">Damage (avg/best)</p>
</div>
</div>
<div class="card--stats-container">
<div class="card--stats-stat">
<p class="card--stats-stat-value">${kdText}</p>
<p class="card--stats-stat-name">K/D</p>
</div>
<div class="card--stats-stat">
<p class="card--stats-stat-value">${roundTo2(100 * (gulagLosses == 0 ? 1 : gulagWins / (gulagLosses + gulagWins)))}%</p>
<p class="card--stats-stat-name">Gulag Win %</p>
</div>
</div>
`;

      const card = document.createElement('div');
      card.className = 'card'
      card.innerHTML = html;

      return card;
    };

    data.filter(it => _corePlayerNames.map(it => it.toLowerCase()).includes(it.player_id)).forEach(rowData => {
      const s = rowData.stats;
      const card = cardWithConfig(rowData.player_id, s.numGames, s.wins, s.top5, s.top10, s.gulagKills, s.gulagDeaths, s.kills, s.deaths, s.damageDone, s.maxKills, s.maxDamage);
      container.appendChild(card);
    });
  };

  const initialize = async () => {
    _queryParams = new URLSearchParams(window.location.search);
    if (window.location.search == "") {
      let params = '?mode=by-stat&stat=kdratio&timeframe=lifetime';
      if (_queryParams.get('names')) {
        params += `&names=${_queryParams.get('names')}`;
      }
      _queryParams = new URLSearchParams(params);
    }

    await loadInitialData();
    const updatedAt = new Date(_metaInfo.updatedAt);
    const formatted = updatedAt.toLocaleString('en-US', { hour: "numeric", minute: "numeric" });
    document.querySelector('.last-updated-text').innerHTML = `Last Updated: ${formatted}`;

    _chart = buildChart();

    const redirect = (stat, timeframe) => {
      stat = stat ? stat : 'kdratio';
      timeframe = timeframe ? timeframe : 'lifetime';
      let url = `/index.html?mode=by-stat&stat=${stat}&timeframe=${timeframe}`;
      if (_queryParams.get('names')) {
        url += `&names=${_queryParams.get('names')}`;
      }
      window.location = url;
    };

    const statDropdown = configureStatDropdown();
    statDropdown.addEventListener('change', e => {
      redirect(e.target.value, _queryParams.get('timeframe'));
    });

    const seasonDropdown = configureSeasonDropdown();
    seasonDropdown.addEventListener('change', e => {
      redirect(_queryParams.get('stat'), e.target.value);
    });

    populateGameRecordsTable();
    populateLifetimeRecordsTable();
    populateTeamRecordsTable();
    populateRecentMatches();
    populateRecentSessions();

    switch (_queryParams.get('mode')) {
      case 'by-stat': {
        setSeriesByBakedStat(_queryParams.get('stat'), _queryParams.get('timeframe'));
        break;
      }
      default: {
        console.warn(`unknown mode [${_queryParams.get('mode')}]`);
        break;
      }
    }
  };

  window.initialize = initialize;
})();
