#!/bin/bash
# Alternativ uden GitHub: henter fra Gitea, bygger lokalt og genstarter kun ved ændringer.
# Kræver git på Tower, en .env i mappen, og at mappen er et git clone af dit Gitea-repo.
cd /mnt/user/appdata/folke-app || exit 1
git fetch -q || exit 1
[ "$(git rev-parse HEAD)" = "$(git rev-parse '@{u}')" ] && [ "$1" != "force" ] && exit 0
git pull -q
docker build -q -t folke-app .
docker rm -f folke >/dev/null 2>&1
docker run -d --name folke --restart unless-stopped --env-file .env \
  -e STATE_FILE=/data/state.json -v "$PWD/data:/data" -p 6660:8080 folke-app
