import * as fs from 'fs';
const API = require('call-of-duty-api')();

const USERNAME = process.env.COD_USERNAME;
const PASSWORD = process.env.COD_PASSWORD;
const COD_DATADIR = process.env.COD_DATADIR;
const OUTDIR=`${COD_DATADIR}/fetcher/output`;

const codApiBatchLimit = 20;
const codApiMatchResultLimit = 1000;
const requestBatchLimit = 10;

// Typings

type PlayerMapping = { playerName: string; activisionPlatform: string; activisionTag: string; unoId: string };
type ResultError = { status: 'error'; error: string };
type ResultOK<T> = { status: 'ok'; results: T };
type Result<T> = ResultOK<T> | ResultError;
type MatchResults = { multiplayer: any; warzone: any };
type StoredMatchData = { matchId: string; playerUnoId: string };

// Config / data

const playerMappings: Record<string, PlayerMapping[]> = JSON.parse(fs.readFileSync('../config/players.json', 'utf8')).reduce(
  (memo, it) => {
    const accounts = it.accounts.map(account => { return {...account, playerName: it.name}; })
    memo[it.name.toLowerCase()] = accounts;
    return memo;
  },
  {}
);

// DO WORK SON

async function loginIfNeeded() {
  if (!API.isLoggedIn()) {
    await API.login(USERNAME, PASSWORD);
  }
}

function isResultError(e: ResultError | any): e is ResultError {
  return (e as ResultError).status === 'error';
}

function getAlreadyDownloadedMatches() {
  const files: string[] = fs.readdirSync(OUTDIR);
  const results: StoredMatchData[] = [];
  files.forEach(file => {
    const matches = file.match(/match_(\d+)_(\d+)\.json/i);
    if (!matches) return;
    results.push({ matchId: matches[1], playerUnoId: matches[2] });
  });
  return results.reduce((memo: Record<string, StoredMatchData[]>, item) => {
    const playerResults = memo[item.matchId] || [];
    playerResults.push(item);
    memo[item.matchId] = playerResults;
    return memo;
  }, {});
}

async function downloadMatchesByBatch(
  matches: any[],
  playerMapping: PlayerMapping,
  mode: 'mp' | 'wz',
  previouslyDownloadedMatches: Record<string, StoredMatchData[]>
) {
  console.log(`downloadMatchesByBatch called for [${playerMapping.activisionTag}] [${mode}] [${matches.length}]`);
  let batch = [];
  for (let matchIdx = 0; matchIdx < matches.length; matchIdx++) {
    const match = matches[matchIdx];
    const downloadedPlayers = previouslyDownloadedMatches[match.matchId];
    const alreadyDownloadedForPlayer =
      downloadedPlayers && downloadedPlayers.find(it => it.playerUnoId === playerMapping.unoId) != null;
    if (!alreadyDownloadedForPlayer) {
      // console.log(
      //   `[${match.matchId}] [${match.timestamp}] not already downloaded for [${playerMapping.unoId}] [${playerMapping.activisionTag}]`
      // );
      batch.push(match);
    } else {
      // console.log(
      //   `[${match.matchId}] already downloaded for [${playerMapping.unoId}]`
      // );
    }

    if (batch.length == codApiBatchLimit * requestBatchLimit || matchIdx == matches.length - 1) {
      let batches = [];
      for (let batchIdx = 0; batchIdx < batch.length; batchIdx += codApiBatchLimit) {
        batches.push(batch.slice(batchIdx, batchIdx + codApiBatchLimit));
      }
      batches = batches.filter(it => it.length > 0);
      if (batches.length > 0) {
        console.log('   fetching batch');

        await Promise.all(batches.map(it => getMatches(playerMapping, mode, it))).then(resultBatches => {
          const counts = resultBatches.map(it => (isResultError(it) ? '-' : it.length));
          console.log(`        [${resultBatches.length}] [${counts.join(',')}] results`);
          resultBatches.forEach((resultBatch, batchIdx) => {
            if (isResultError(resultBatch)) {
              const batchForResult = batches[batchIdx];
              console.error(
                `batch [${batchForResult[0].matchId} ${batchForResult[0].timestamp}]-[${
                  batchForResult[batchForResult.length - 1].matchId
                } ${batchForResult[batchForResult.length - 1].timestamp}] failed`
              );
              console.error(resultBatch.error);
              return;
            }
            resultBatch.forEach((result, idx) => {
              const matchForResult = batches[batchIdx][idx];
              if (isResultError(result)) {
                console.error(`[${matchForResult.matchId} ${matchForResult.timestamp}] failed`);
                console.error(result.error);
                return;
              }
              fs.writeFileSync(
                `${OUTDIR}/match_${matchForResult.matchId}_${playerMapping.unoId}.json`,
                JSON.stringify(result.results)
              );
              // console.log(`downloaded [${matchForResult.matchId}] for [${playerMapping.unoId}]`);
            });
          });
        });
      }
      batch = [];
    }
  }
}

async function getMatches(
  player: PlayerMapping,
  mode: 'mp' | 'wz',
  matches: { timestamp: number; matchId: string }[]
): Promise<ResultError | Result<any>[]> {
  if (matches.length == 0) {
    return [];
  }

  const sortedMatches = matches.sort((a, b) => a.timestamp - b.timestamp);
  const firstMatch = sortedMatches[0];
  const lastMatch = sortedMatches[sortedMatches.length - 1];
  // console.log(`[${firstMatch.matchId} ${lastMatch.matchId}] start`);

  try {
    let allResults;
    switch (mode) {
      case 'mp':
        allResults = await API.MWcombatmpdate(
          player.activisionTag,
          firstMatch.timestamp,
          lastMatch.timestamp + 1,
          player.activisionPlatform
        );
        break;
      case 'wz':
        allResults = await API.MWcombatwzdate(
          player.activisionTag,
          firstMatch.timestamp,
          lastMatch.timestamp + 1,
          player.activisionPlatform
        );
        break;
    }

    const returnedMatches: any[] = allResults.matches ?? [];
    // console.log('------------ Requested');
    // console.dir(sortedMatches.map(res => res.matchId));
    // console.log('------------');
    // console.log('------------ Returned');
    // console.dir(returnedMatches.sort((a, b) => a.utcStartSeconds - b.utcStartSeconds).map(res => res.matchID));
    // console.log('------------');
    const results = matches.map<Result<any>>(it => {
      const returnedMatch = returnedMatches.find(res => res.matchID === it.matchId);
      if (returnedMatch) {
        return { status: 'ok', results: returnedMatch };
      } else {
        return {
          status: 'error',
          error: `[${mode}] match not found [ts ${it.timestamp}] [id ${it.matchId}] [pid ${player.activisionPlatform} ${player.unoId} ${player.activisionTag}}]`,
        };
      }
    });

    // console.log(`[${firstMatch.matchId} ${lastMatch.matchId}] success`);
    return results;
  } catch (error) {
    // console.log(`[${firstMatch.matchId} ${lastMatch.matchId}] error`);
    return { status: 'error', error };
  }
}

async function exhaustivelyRetrieveMatches(tag: string, platform: string, getMoreFn: (tag: string, start: number, end: number, platform: string)=> Promise<any[]>) {
  let start = 0, end = 0;
  let results = [];
  let keepGoing = true;

  while(keepGoing) {
    let newResults = await getMoreFn(tag, start, end, platform);
    results = results.concat(newResults);
    if (0 <= newResults.length && newResults.length < codApiMatchResultLimit) {
      keepGoing = false;
    } else {
      end = newResults[newResults.length - 1].timestamp;
    }
  }
  return results;
}

async function main(mappings: PlayerMapping[]): Promise<Result<any>> {
  let results = { multiplayer: null, warzone: null } as MatchResults;

  try {
    for (let idx = 0; idx < mappings.length; idx++) {
      const player = mappings[idx];
      const stats = await Promise.all([
        // NOTE(jpr): disable MP until we figure out how we want to surface the data
        Promise.resolve([]), // exhaustivelyRetrieveMatches(player.activisionTag, player.activisionPlatform, API.MWfullcombatmpdate.bind(API)),
        exhaustivelyRetrieveMatches(player.activisionTag, player.activisionPlatform, API.MWfullcombatwzdate.bind(API)),
      ]);
      results.multiplayer = (results.multiplayer ?? []).concat(stats[0]);
      results.warzone = (results.warzone ?? []).concat(stats[1]);
    }
  } catch (error) {
    return { status: 'error', error } as Result<any>;
  }

  return { status: 'ok', results } as Result<any>;
}

/*
 * CLI handler
 */

(async () => {
  if (!COD_DATADIR) {
    console.error('Must set envvar COD_DATADIR');
    process.exit(1);
  }
  if (!fs.statSync(COD_DATADIR).isDirectory) {
    console.error(`Data dir doesnt exist [${COD_DATADIR}]`);
    process.exit(1);
  }

  if (!USERNAME) {
    console.error('Must set envvar [COD_USERNAME]');
    process.exit(1);
  }

  if (!PASSWORD) {
    console.error('Must set envvar [COD_PASSWORD]');
    process.exit(1);
  }

  try {
    if (!fs.existsSync(OUTDIR)) {
      fs.mkdirSync(OUTDIR, {recursive: true});
    }

    await loginIfNeeded();

    const playerNames = process.argv[2] ? [process.argv[2]] : Object.keys(playerMappings);

    const results = {} as any;
    const jobs = playerNames.map(name => {
      return new Promise(async (resolve, reject) => {
        const playerData = playerMappings[name];
        if (!playerData) {
          return reject(`No player found for [${name}]`);
        }
        const data = await main(playerData);
        if (data.status === 'error') {
          return reject(data.error);
        }
        results[name] = data.results;
        return resolve();
      });
    });
    await Promise.all(jobs);

    const previouslyDownloadedMatches = getAlreadyDownloadedMatches();

    for (let nameIdx = 0; nameIdx < playerNames.length; nameIdx++) {
      const name = playerNames[nameIdx];
      const mappings = playerMappings[name];
      for (let mappingIdx = 0; mappingIdx < mappings.length; mappingIdx++) {
        const playerMapping = mappings[mappingIdx];
        // NOTE(jpr): disable MP until we figure out how we want to surface the data
        // await downloadMatchesByBatch(results[name].multiplayer, playerMapping, 'mp', previouslyDownloadedMatches);
        await downloadMatchesByBatch(results[name].warzone, playerMapping, 'wz', previouslyDownloadedMatches);
      }
    }
  } catch (err) {
    console.log('--------------------------------------------------------------------------------');
    console.error('ERROR:');
    console.error(err);
    process.exit(1);
  }
})();
