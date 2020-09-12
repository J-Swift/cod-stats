# Call of Duty stats tracker

A simple to setup / run micro site for tracking individual and team stats for COD: Modern Warfare (specifically Warzone at the moment).

This project is intended to be a way to easily:

1. Figure out the true performance of members of a playgroup, rather than just relying on, e.g., lifetime K/D ratio
1. Figure out if you are improving over time in certain categories, e.g., gulag win % or Damage / Kill

It leverages an existing (mostly undocumented?) activision API that powers my.callofduty.com to pull the data. It then parses that data into a sqlite database and generates statistics to then be uploaded to an S3 static website for viewing/sharing with others.

Note that this project is very much intended to be used for a group of players that regularly play together. Some of the sql reporting is specific to 'full squad games' (i.e. you played trios and all 3 players were from your play group). That said, it can be run just fine to track individual progress over time.


## Screenshots

You can see an live example running at https://codstats-frontend.s3.amazonaws.com/index.html

Main page / Player page

<img src="https://github.com/J-Swift/cod-stats/raw/master/gh_images/main-page.png" width="300px" />  <img src="https://github.com/J-Swift/cod-stats/raw/master/gh_images/player-page-cropped.png" width="300px" />


## Requirements:

1. Docker
1. GNU Make

Neither of these are _actually_ required, but it is very much the preferred setup. If you run the equivalent make targets directly, there are more dependencies you need to ensure are setup correctly (e.g. aws cli, jq, sqlite). Have a look at the `Dockerfile` and `Makefile` to get an idea of how you might accomplish this.

On windows I've only verified that everything works if run via `git-bash` (typically located at `C:\Program Files\Git\bin\bash.exe`).


## Getting started

Before running you will want to create a `config/players.json` and `config/env` file from the example files provided (`config/players.json.example` and `config/env.example`). See the 'Setting up players.json' section below for help.

The first time you setup the project you want to run `make ensure-bootstrap` to be sure everything is setup and configured correctly. After that you can run `make docker-run` whenever you want to fetch and publish new data to your s3 website.

In other words, do this the first time:

```sh
cp config/env.example config/env
# ... fill in env ...

cp config/players.json.example config/players.json
# ... fill in players.json ...

make ensure-bootstrap && make-docker-run
```

and then to update with newer data in the future, just run this:
```
make docker-run
```


## Setting up players.json

In order to have a correct `players.json` there are a couple things to keep in mind.

First, you _need_ at least 1 'core' player, but may also have extra 'non-core' players. A core player is someone who should be tracked and taken into account when figuring out "best of" stats, etc. A non-core player will still be shown in the charts (though they won't be enabled by default), but will not be taken into account for team/player leaderboards. I use non-core players to track a couple pros so that we have a baseline of what "good" numbers might look like for a given chart.

If you do add pro players to be tracked, keep in mind that pro players generally play a lot more games than non-pros, and so the number of files and size of the DB can grow much larger which tracking them. Also, the initial sync can run into rate limiting issues because of this.

Second, you need all 3 of the player's platform, tag, and uno id for every player. To find the uno id for a player, first run `make docker-query-player ARGS='search {player-name}'` and find the most likely account based on K/D ratio, number of games, and platform. Then, use the platform and tag to call `make docker-query-player ARGS='id {platform} {tag}'`. This should list their uno id. Its too expensive in API calls to automatically lookup uno ids for each possible player in the search, so these are 2 separate steps for now.

```sh
$ make docker-query-player ARGS='search JamesSwift'
> found [1] results...

[battle] [JamesSwift#1805] [unoid undefined]
    [0.87 kd] [501 games]

# Since the unoid is undefined above, we need to query it separately...
$ make docker-query-player ARGS='id battle JamesSwift#1805'
[battle] [JamesSwift#1805] [unoid 2391270]
```

Note that a single player entry in `players.json` can be associated with multiple platform/tag/uno-id configurations, in case you want to merge account stats together into one entry. This happens sometimes if people change their player tag, or start a new account.


## System architecture

There are 3 main projects/phases to the system: the Fetcher, Parser, and Frontend. They are setup as distinct steps to help with decoupling, maintainability, and idempotency. The system is pretty resilient, you can fix most errors by just deleting the DB and/or match files and pulling the data from the API again.


### Fetcher

This is a typescript project which takes care of calling the activision API and downloading all the stats for any games it doesnt know about for all the players.

The fetcher project also has additional helper scripts for checking api credentials and querying player ids. These all live here because they all rely on the same [Call of Duty NPM package](https://github.com/Lierrmm/Node-CallOfDuty).


### Parser

This is a bash script which takes the previously downloaded matches which are stored on the filesystem as flat json files, and creates / updates a sqlite database with the data. The database only has a couple _real_ tables, the rest are virtual (aka views). This is so that migrations are infrequently needed, and storage size is minimized. This has performance implications, but this hasn't been a concern yet when running locally. It _can_ come into play when running on, e.g., EFS on AWS.


### Frontend

This is a bash script which takes the sqlite file and generates static JSON-ish reports on various aspects of the players/seasons. It then has some html/css/JS that consumes these reports statically. Note this is vanilla CSS/JS, no frameworks at the moment to keep complexity down. I may move to a component-based JS framework later, its just getting to be annoying enough without one.

The frontend project also has a deploy script which pushes the generated files to S3.


## FAQ

**Q**: What do I do if I get a Rate Limit error from the activision API?  
**A**: This is fine, just dont run the project again for a few hours and it should automatically reset. The code can keep most of its interim progress so that you won't constantly be rate limited after an initial sync.

**Q**: I messed up my database / match files, how do I fix it?  
**A**: You can safely delete the database and it will be recreated on demand. Same with the match files, but I would recommend deleting the database as well in that case to be sure bad data didn't get inserted.

**Q**: How do I automatically update the stats?  
**A**: The easiest way would be to run a local cronjob (e.g. every 20-30 minutes). I personally have the docker container running in AWS ECS as a scheduled task so that I dont need my computer to be on, using EFS as durable storage so each job takes the minimum amount of time to complete. This is much more difficult to setup however, so its not officially supported. If you _do_ set this up for yourself, you can use the `make docker-push` command to build and update your ECR image.

**Q**: I'm running this on ECS with EFS like you said, but its going really slow! What gives?  
**A**: The burstable IOPS mode of EFS is not a good fit for our use case as we read/write a lot of small data as well as open/close the sqlite file repeatedly. Its very easy to deplete your burst credits and so you will want to enabled Provisioned IOPS for EFS to get around this, or set a much longer cron window (probably 1 hour at the minimum).

**Q**: Warzone is great, but what about multiplayer stats?  
**A**: The support for pulling / ingesting the multiplayer stats is all in place, I just haven't gotten around to designing the UI/UX/metrics of it. There are a lot of game modes to think about and its tough to have useful metrics and keep the mobile UI workable.

**Q**: Why do I need to put a players platform, tag, and uno id in the `players.json` file?  
**A**: Ideally, this would only require uno id, since thats what the DB uses to track and distinguish players. The problem is that the activision API is not consistent in how it treats uno id when you use certain endpoints though. For example, if you ask for all the matches for a given player using their uno id, it might return nothing. If you ask using platform/tag then it returns all their games.

**Q**: Why sqlite?  
**A**: Sqlite does a ton out of the box and is able to be stored as a single file, which makes deployment and project setup much easier. It also keeps deployment costs minimal, since you only need durable disk storage, and dont need to pay for a managed DB instance. I think in the future this could eventually move to Postgres.

**Q**: Why static files for the frontend?  
**A**: Again, this is for deployment and configuration ease of use. Its much easier to setup an S3 static site for someone than it is for me to assist in hosting as a real API service with real DB calls. This has worked nicely so far, but might move to a proper backend at some point as filter/sort options become more prevalent.

**Q**: What are these random `default.nix` files?  
**A**: This is for [Nix package manager](https://nixos.org/download.html), you can ignore those. I use `Nix` for my local sandboxing instead of `docker`.

**Q**: How do I set player photos?  
**A**: This is a bit of a hack at the moment. You need to put a .jpg (_MUST BE .JPG_!) file into `frontend/resources/images/players` named with the player namer from `players.json`. So, if you have a player in `players.json` with `name: 'Jimmy'` then you need a file at `frontend/resources/images/players/jimmy.jpg`.

**Q**: What is a session?  
**A**: A session is currently defined as one or more games that occur at least 2 hours after any other games. So if you played 3 games, then waited 2 hours and played another game, that would be 2 sessions. However, if you played the 4th game just 1.5 hours later, it would be considered to be a part of the same session. The 2 hours is arbitrary (set in the `parse_matches.sh` `create_tables` function), and might be adjusted in the future.

**Q**: How do I test the site locally?  
**A**: Since the default setup encapsulates in the Docker container, you need to run the `run_and_deploy.sh` script locally and then serve those files to your browser. I use pythons built in http server (`cd .data/frontend/output && python -m SimpleHTTPServer`).

**Q**: What can I use to browse the data in the DB?  
**A**: I use [DB Browser for SQLite](https://github.com/sqlitebrowser/sqlitebrowser) on my Mac


## TODOs

- Add multiplayer reporting + UI. The stats fetching is implemented and storage is mostly implemented.
- Complete game mode mappings
- More robust filtering/selection. e.g. allow breakdown of stats by solo/duos/trios/quads
- Add weapon/loadout statistics
- Add CDK based deployment scripts
