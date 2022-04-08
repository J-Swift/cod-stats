import * as fs from 'fs';
const API = require('call-of-duty-api')();

const SSO = process.env.COD_SSO;
const COD_DATADIR = process.env.COD_DATADIR;
const OUTDIR = `${COD_DATADIR}/fetcher/output`;
const RATE_LIMIT_FILE = `${COD_DATADIR}/fetcher/rate_limit_until.json`;
const FAILURES_FILE = `${COD_DATADIR}/fetcher/failure_stats.json`;

const codApiBatchLimit = 20;
const codApiMatchResultLimit = 1000;
const requestBatchLimit = 10;
const initialRateLimitBackoffMins = 60;
const maxFailuresBeforeCutoff = 50;

// Typings

type PlayerMapping = { playerName: string; activisionPlatform: string; activisionTag: string; unoId: string };
type ResultError = { status: 'error'; error: string };
type ResultOK<T> = { status: 'ok'; results: T };
type Result<T> = ResultOK<T> | ResultError;
type MatchResults = { multiplayer: any; warzone: any };
type StoredMatchData = { matchId: string; playerUnoId: string };
type RateLimitInfo = { lastBackoffMins: number; delayUntilUnix: number };

// Config / data

const playerMappings: Record<string, PlayerMapping[]> = JSON.parse(
  fs.readFileSync('../config/players.json', 'utf8')
).reduce((memo, it) => {
  const accounts = it.accounts.map(account => {
    return { ...account, playerName: it.name };
  });
  memo[it.name.toLowerCase()] = accounts;
  return memo;
}, {});

// Rate limiting

function currentUnixTimeSeconds() {
  return Math.trunc(Date.now() / 1000);
}

function getRateLimitInfo(): RateLimitInfo | null {
  if (!fs.existsSync(RATE_LIMIT_FILE)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(RATE_LIMIT_FILE, 'utf8')) as RateLimitInfo;
}

function rateLimitBackoffRemaining() {
  const rateLimitInfo = getRateLimitInfo();
  if (rateLimitInfo == null) {
    return 0;
  }
  const currentUnix = currentUnixTimeSeconds();
  return rateLimitInfo.delayUntilUnix - currentUnix;
}

function isRateLimitError(error: any) {
  if (typeof error == 'string') {
    // TODO(jpr): patch lib to provide better error object
    return error.indexOf('429') >= 0 || error.indexOf('403') >= 0;
  }
  return false;
}

function writeNewRateLimitInfo() {
  const rateLimitInfo = getRateLimitInfo() ?? { lastBackoffMins: initialRateLimitBackoffMins / 2, delayUntilUnix: 0 };
  // exponential backoff
  const newBackoffMins = rateLimitInfo.lastBackoffMins * 2;
  const newRateLimitInfo = { lastBackoffMins: newBackoffMins, delayUntilUnix: currentUnixTimeSeconds() + 60 * newBackoffMins };
  console.info(`Backing off for [${newBackoffMins}] mins`);
  fs.writeFileSync(RATE_LIMIT_FILE, JSON.stringify(newRateLimitInfo));
}

function deleteRateLimitInfo() {
  if (!fs.existsSync(RATE_LIMIT_FILE)) {
    return;
  }
  fs.unlinkSync(RATE_LIMIT_FILE);
}

// Failure tracking

type FailureData = { [matchId: string]: number };
class FailureInfo {
  private readonly data: FailureData;

  constructor() {
    this.data = this.getFailureData() ?? {} as FailureData
  }

  count(matchId: string): number {
    return this.data[matchId] ?? 0;
  }

  increment(matchId: string): number {
    const newCount = (this.count(matchId) ?? 0) + 1;
    this.data[matchId] = newCount;
    return newCount;
  }

  remove(matchId: string) {
    delete this.data[matchId];
  }

  writeToDisk() {
    fs.writeFileSync(FAILURES_FILE, JSON.stringify(this.data));
  }

  private getFailureData(): FailureData | null {
    if (!fs.existsSync(FAILURES_FILE)) {
      return null;
    }

    return JSON.parse(fs.readFileSync(FAILURES_FILE, 'utf8')) as FailureData;
  }
};

// DO WORK SON

async function loginIfNeeded() {
  if (!API.isLoggedIn()) {
    await API.loginWithSSO(SSO);
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
  previouslyDownloadedMatches: Record<string, StoredMatchData[]>,
  failureInfo: FailureInfo
) {
  console.log(`downloadMatchesByBatch called for [${playerMapping.activisionTag}] [${mode}] [${matches.length}]`);
  let batch = [];
  for (let matchIdx = 0; matchIdx < matches.length; matchIdx++) {
    const match = matches[matchIdx];
    const downloadedPlayers = previouslyDownloadedMatches[match.matchId];
    const alreadyDownloadedForPlayer =
      downloadedPlayers && downloadedPlayers.find(it => it.playerUnoId === playerMapping.unoId) != null;
    if (!alreadyDownloadedForPlayer && failureInfo.count("" + match.matchId) < maxFailuresBeforeCutoff) {
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
                const failCount = failureInfo.increment("" + matchForResult.matchId);
                console.error(`[match-${matchForResult.matchId} ts-${matchForResult.timestamp}] failed (#${failCount})`);
                console.error(result.error);
                return;
              }
              fs.writeFileSync(
                `${OUTDIR}/match_${matchForResult.matchId}_${playerMapping.unoId}.json`,
                JSON.stringify(result.results)
              );
              failureInfo.remove("" + matchForResult.matchId);
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

async function exhaustivelyRetrieveMatches(
  tag: string,
  platform: string,
  getMoreFn: (tag: string, start: number, end: number, platform: string) => Promise<any[]>
) {
  let start = 0,
    end = 0;
  let results = [];
  let keepGoing = true;

  while (keepGoing) {
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

  if (!SSO) {
    console.error('Must set envvar [COD_SSO]');
    process.exit(1);
  }

  const rateLimitRemaining = rateLimitBackoffRemaining();
  if (rateLimitRemaining > 0) {
    const remainingText = rateLimitRemaining < 60 ? '< 1' : Math.trunc(rateLimitRemaining/60);
    console.error(`Waiting [${remainingText}] more mins because of rate limiting`);
    process.exit(1);
  }

  try {
    if (!fs.existsSync(OUTDIR)) {
      fs.mkdirSync(OUTDIR, { recursive: true });
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
    const failureInfo = new FailureInfo();

    for (let nameIdx = 0; nameIdx < playerNames.length; nameIdx++) {
      const name = playerNames[nameIdx];
      const mappings = playerMappings[name];
      for (let mappingIdx = 0; mappingIdx < mappings.length; mappingIdx++) {
        const playerMapping = mappings[mappingIdx];
        // NOTE(jpr): disable MP until we figure out how we want to surface the data
        // await downloadMatchesByBatch(results[name].multiplayer, playerMapping, 'mp', previouslyDownloadedMatches);
        await downloadMatchesByBatch(results[name].warzone, playerMapping, 'wz', previouslyDownloadedMatches, failureInfo);
      }
    }

    failureInfo.writeToDisk();
    deleteRateLimitInfo();
  } catch (err) {
    console.log('--------------------------------------------------------------------------------');
    console.error('ERROR:');
    console.error(err);
    if (isRateLimitError(err)) {
      writeNewRateLimitInfo();
    }
    process.exit(1);
  }
})();
