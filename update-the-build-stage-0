#!/usr/bin/env bash

set -o verbose
set -o errexit

sudo docker stop cocalc-test || true
sudo docker rm cocalc-test || true

git pull
time sudo docker build --build-arg commit="$(git ls-remote -h https://github.com/sagemathinc/cocalc master | awk '{print $1}')" --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" -t cocalc -f Dockerfile-no-agpl .
sudo docker tag cocalc:latest sagemathinc/cocalc
sudo docker run --name=cocalc-test -d -v ~/cocalc-test:/projects -p 4043:443 sagemathinc/cocalc
