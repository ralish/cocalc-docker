#!/usr/bin/env bash

set -o verbose
set -o errexit

sudo docker stop cocalc-no-agpl-test || true
sudo docker rm cocalc-no-agpl-test || true

git pull
time sudo docker build --build-arg commit="$(git ls-remote -h https://github.com/sagemathinc/cocalc master | awk '{print $1}')" --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" -t cocalc -f Dockerfile-no-agpl .
sudo docker tag cocalc:latest sagemathinc/cocalc-no-agpl
sudo docker run --name=cocalc-no-agpl-test -d -v ~/cocalc-no-agpl-test:/projects -p 4044:443 sagemathinc/cocalc-no-agpl
