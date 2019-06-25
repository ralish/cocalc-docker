#!/usr/bin/env bash

set -v
sudo docker stop cocalc-no-agpl-test
sudo docker rm cocalc-no-agpl-test
sudo docker push sagemathinc/cocalc-no-agpl
