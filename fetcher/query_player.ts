const API = require('call-of-duty-api')();

const USERNAME = process.env.COD_USERNAME;
const PASSWORD = process.env.COD_PASSWORD;

// Typings

type ResultError = { status: 'error'; error: string };
type ResultOK<T> = { status: 'ok'; results: T };
type Result<T> = ResultOK<T> | ResultError;

// DO WORK SON

async function loginIfNeeded() {
  if (!API.isLoggedIn()) {
    await API.login(USERNAME, PASSWORD);
  }
}

function isResultError(e: ResultError | any): e is ResultError {
  return (e as ResultError).status === 'error';
}

async function searchTag(username: string, limit: number = 10) {
  let res = await API.FuzzySearch(username, 'all');
  console.log(`> found [${res.length}] results...`);
  if (res.length > limit) {
    console.log(`> limiting to [${limit}]`);
    res = res.slice(0, limit);
  }
  console.log();

  const allStatPs = res.map(it => {
    const platform = it.platform.toLowerCase() == 'steam' ? 'battle' : it.platform;
    return API.MWwzstats(it.username, platform)
      .then(stats => {
        return { status: 'ok', results: stats.lifetime.mode.br.properties };
      })
      .catch(error => {
        return { status: 'error', error };
      });
  });
  const allStats: Result<any>[] = await Promise.all(allStatPs);

  res.forEach(async (it, idx) => {
    const stats = allStats[idx];
    if (isResultError(stats)) {
      console.log(`[${it.platform}] [${it.username}] [unoid ${it.accountId}]\n    ERROR: ${stats.error}`);
    } else {
      console.log(
        `[${it.platform}] [${it.username}] [unoid ${it.accountId}]\n    [${(
          Math.round(stats.results.kdRatio * 100) / 100
        ).toFixed(2)} kd] [${stats.results.gamesPlayed} games]`
      );
    }
  });
}

async function lookupUnoId(platform: string, username: string) {
  platform = platform.toLowerCase() == 'steam' ? 'battle' : platform;
  const stats = await API.MWcombatwz(username, platform)
    .then(res => {
      return { status: 'ok', results: res.matches[0].player.uno };
    })
    .catch(error => {
      return { status: 'error', error };
    });

  if (isResultError(stats)) {
    console.log(`ERROR: ${stats.error}`);
  } else {
    console.log(`[${platform}] [${username}] [unoid ${stats.results}]`);
  }
}

/*
 * CLI handler
 */

(async () => {
  if (!USERNAME) {
    console.error('Must set envvar [COD_USERNAME]');
    process.exit(1);
  }

  if (!PASSWORD) {
    console.error('Must set envvar [COD_PASSWORD]');
    process.exit(1);
  }

  const args = process.argv.slice(2);
  const mode = args[0];

  try {
    await loginIfNeeded();
    switch(mode) {
      case 'search': {
        const playerTag = args[1];
        if (!playerTag) {
          console.error('ERROR: must provide a player tag');
          process.exit(1);
        }
        await searchTag(playerTag);
        break;
      }
      case 'id': {
        const playerPlatform = args[1];
        const playerTag = args[2];
        if (! playerPlatform || !playerTag) {
          console.error('ERROR: must provide both a player name and tag');
          process.exit(1);
        }
        await lookupUnoId(playerPlatform, playerTag);
        break;
      }
      default: {
        console.error(`Unrecognized mode [${mode}]. Please provide one of [search, id].`);
        process.exit(1);
      }
    }
  } catch (err) {
    console.log('--------------------------------------------------------------------------------');
    console.error('ERROR:');
    console.error(err);
    process.exit(1);
  }
})();
