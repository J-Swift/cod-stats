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

  let _queryParams = null;
  let _playerStatsInfo = null;
  let _gamesInfo = [];
  let _sessionsInfo = [];

  const loadPlayerStatsData = async (playerName) => {
    let playerFound = true;

    const data = await fetch(`/data/output/${playerName}_player_stats.json`)
      .then(response => {
        if (response.status == 404) {
          throw Error(response.statusText);
        }
        return response.text();
      })
      .then(it => JSON.parse(it))
      .catch(e => {
        playerFound = false;
        console.error(e)
      });

    if (!playerFound) {
      return;
    }
    _playerStatsInfo = data;
  };

  const loadGamesData = async (playerName, titlizedName) => {
    let playerFound = true;
    const data = await fetch(`/data/output/${playerName}_lifetime_game_wz.json`)
      .then(response => {
        if (response.status == 404) {
          throw Error(response.statusText);
        }
        return response.text();
      })
      .then(it => {
        const entries = JSON.parse(it);

        return entries.filter(it => it.stats != null).map(it => {
          const dt = new Date(it.date);
          const stats = it.stats;
          return { ...stats.raw, start: dt };
        });
      })
      .catch(e => {
        playerFound = false;
        console.error(e)
      });

    if (!playerFound) {
      document.querySelector('.games-text').innerHTML = `No games found for [${titlizedName}]`;
      return;
    }
    _gamesInfo = data.sort((a, b) => b.start - a.start).slice(0, 25);

    document.querySelector('.games-text').innerHTML = `Last ${_gamesInfo.length} games:`;
  };

  const loadSessionsData = async (playerName, titlizedName) => {
    let playerFound = true;
    const data = await fetch(`/data/output/sessions_${playerName}.json`)
      .then(response => {
        if (response.status == 404) {
          throw Error(response.statusText);
        }
        return response.text();
      })
      .then(it => JSON.parse(it))
      .catch(e => {
        playerFound = false;
        console.error(e)
      });

    if (!playerFound) {
      document.querySelector('.sessions-text').innerHTML = `No sessions found for [${titlizedName}]`;
      return;
    }
    _sessionsInfo = data.sessions.sort((a, b) => a.start - b.start);

    document.querySelector('.sessions-text').innerHTML = `${titlizedName} has played ${_sessionsInfo.length} sessions:`;
  };

  const loadUpdatedAt = async (playerName) => {
    let playerFound = true;
    const data = await fetch(`/data/output/sessions_${playerName}_updated_at.json`)
      .then(response => {
        if (response.status == 404) {
          throw Error(response.statusText);
        }
        return response.text();
      })
      .then(it => JSON.parse(it))
      .catch(e => {
        playerFound = false;
        console.error(e)
      });

    if (!playerFound) {
      return;
    }

    const updatedAt = new Date(data.updatedAt);
    const formatted = updatedAt.toLocaleString('en-US', { hour: "numeric", minute: "numeric" });
    document.querySelector('.last-updated-text').innerHTML = `Last Updated: ${formatted}`;
  };

  const loadInitialData = async () => {
    const playerName = _queryParams.get('player').toLowerCase()
    const titlizedName = playerName[0].toUpperCase() + playerName.substr(1);
    document.querySelector('.profile-container--name').innerHTML = titlizedName;
    document.querySelector('.profile-container--image').src = `/resources/images/players/${playerName}.jpg`;
    await Promise.all([loadPlayerStatsData(playerName), loadGamesData(playerName, titlizedName), loadSessionsData(playerName, titlizedName), loadUpdatedAt(playerName)]);
  };

  const hideEmptyModeMessage = () => {
    document.querySelector('#empty-mode-message').style.display = 'none';
  };
  const setEmptyMessage = (msg) => {
    const el = document.querySelector('#empty-mode-message');
    el.innerHTML = msg;
    el.style.display = 'absolute';
  };

  const populatePlayerStats = async () => {
    if (_playerStatsInfo == null) {
      return;
    }

    const container = document.querySelector('.player-stats');
    const data = _playerStatsInfo;

    const cardWithConfig = (name, numGames, metrics, placements) => {
      let html = `
<div style="display: flex; justify-content: space-between; align-items: center; text-align: center; line-height: 1.2">
  <h5 class='player-stats--card-title'>${name}</h5>
  <p class="card--games-text card-deemphasize">${numGames} ${numGames == 1 ? 'Game' : 'Games'}</p>
</div>
<div class='player-stats--card-section-container'>
`;
      metrics.forEach(metric => {
        html += `
  <div class='player-stats--card-section'>
    <p class='player-stats--card-section-name card-deemphasize'>${metric.name}</p>
    <p class='player-stats--card-section-value'>${metric.value}</p>
  </div>
`
      });
      html += `
</div>
<div class='player-stats--card-section-container'>
`;
      placements.forEach(placement => {
        html += `
  <div class='player-stats--card-section'>
    <p class='player-stats--card-section-name card-deemphasize'>${placement.name}</p>
    <p class='player-stats--card-section-value'>${placement.value}</p>
  </div>
`
      });
      html += `
</div>
`;

      const card = document.createElement('div');
      card.className = 'card player-stats--card';
      card.innerHTML = html;
      return card;
    };

    data.forEach(timePeriod => {
      const card = cardWithConfig(timePeriod.displayName, timePeriod.numGames, timePeriod.metrics, timePeriod.placements);
      container.appendChild(card);
    });
  };

  const populateRecentGames = async () => {
    if (_gamesInfo.length == 0) {
      return;
    }
    const container = document.querySelector('.games-table-container');

    const table = document.createElement('table');
    table.className = 'recent-matches-table sortable-table sort-inverted';
    let html = `
  <thead>
    <tr>
      <th data-sort-default>Time</th>
      <th>Mode</th>
      <th data-sort-method='number'>Place</th>
      <th data-sort-method='number'>Dmg</th>
      <th data-sort-method='number'>K</th>
      <th data-sort-method='number'>D</th>
      <th data-sort-method='number'>K/D</th>
      <th>Gulag</th>
    </tr>
  </thead>
  <tbody>
`;

    _gamesInfo.forEach(it => {
      const dateText = it.start.toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: 'numeric' });
      const kdText = roundTo2(it.deaths == 0 ? it.kills : it.kills / it.deaths);
      let gulagText = "&nbsp;";
      let gulagClassName = "";
      if (it.gulagKills > 0) {
        gulagText = "&#x2714;&#xFE0E;"; // ✔;
        gulagClassName = "gulag-win";
      } else if (it.gulagDeaths > 0) {
        gulagText = "&#x2718;&#xFE0E;"; // ✘;
        gulagClassName = "gulag-loss";
      }
      html += `
    <tr>
      <td data-sort="${it.start.toISOString()}" style="white-space: nowrap;">${dateText}</th>
      <td>${it.mode}</th>
      <td data-sort="${it.teamPlacement}" data-sort-method="number">${it.teamPlacement}&nbsp;/&nbsp;${it.numberOfTeams}</th>
      <td>${it.damageDone}</th>
      <td>${it.kills}</th>
      <td>${it.deaths}</th>
      <td>${kdText}</th>
      <td class="${gulagClassName}">${gulagText}</th>
    </tr>
`;
    });
    html += `
  </tbody>
`;

    table.innerHTML = html;

    const gamesElement = container.querySelector('.games');
    gamesElement.parentNode.replaceChild(table, gamesElement);

    new Tablesort(table, {
      descending: true
    });
  }

  const populateRecentSessions = async () => {
    const container = document.querySelector('.sessions');
    const data = _sessionsInfo;

    const cardWithConfig = (playerText, numGames, numWins, top5s, top10s, gulagWins, gulagLosses, numKills, numDeaths, damageDone, maxKills, maxDamage) => {
      const kdText = roundTo2(numDeaths == 0 ? numKills : numKills / numDeaths);
      const html = `
<div style="display: flex; justify-content: space-between; align-items: center; text-align: center; line-height: 1.2">
  <p class="card--player-text">${playerText}</p>
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

    data.forEach(rowData => {
      const s = rowData.stats;
      const dt = new Date(rowData.start).toLocaleDateString('en-US', { month: "short", day: "numeric" });
      const card = cardWithConfig(dt, s.numGames, s.wins, s.top5, s.top10, s.gulagKills, s.gulagDeaths, s.kills, s.deaths, s.damageDone, s.maxKills, s.maxDamage);
      container.appendChild(card);
    });
  };

  const initialize = async () => {
    _queryParams = new URLSearchParams(window.location.search);
    const backButton = document.querySelector('.back-button');
    if (document.referrer != "" && (new URL(document.referrer)).origin == window.location.origin) {
      backButton.href = document.referrer;
    } else {
      backButton.href = '/index.html';
    }

    await loadInitialData();

    populatePlayerStats();
    populateRecentGames();
    populateRecentSessions();
  };

  window.initialize = initialize;
})();
