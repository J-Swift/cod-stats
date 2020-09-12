FROM alpine:latest

RUN apk add --no-cache --update --upgrade coreutils bash npm nodejs sqlite jq aws-cli rsync \
    && rm -rf /var/cache/apk/* \
    && mkdir /opt/app
WORKDIR /opt/app

ENV COD_DATADIR=/opt/data
VOLUME /opt/data

WORKDIR /opt/app/fetcher
COPY fetcher/package.json fetcher/package-lock.json ./
RUN npm install
COPY fetcher .
RUN npm run-script build
WORKDIR /opt/app

WORKDIR /opt/app/parser
COPY parser .
# parser work
WORKDIR /opt/app

WORKDIR /opt/app/frontend
COPY frontend .
# frontend work
WORKDIR /opt/app

WORKDIR /opt/app/deploy
COPY deploy/deploy.sh .
# deploy work
WORKDIR /opt/app

COPY config/players.json ./config/
COPY run_and_deploy.sh ./
CMD ["/bin/bash", "run_and_deploy.sh"]
