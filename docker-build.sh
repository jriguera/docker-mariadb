#!/usr/bin/env bash

DOCKER="docker buildx build --platform linux/arm/v7,linux/arm64/v8,linux/amd64"
# DOCKER="docker build"
NAME="mariadb"


HASH=$(git describe --all --long --dirty --abbrev=10 --tags --always)
REPOSITORY=$(git remote get-url --push origin)
TIME=$(TZ=UTC date '+%FT%T.%N%:z')
BASE=alpine:3.18
TZ=$(timedatectl | awk '/Time zone:/{ print $3 }')

source VERSIONS

pushd docker
    $DOCKER \
      --build-arg REPOSITORY="${REPOSITORY}" \
      --build-arg BASE="${BASE}" \
      --build-arg VERSION="${VERSION}" \
      --build-arg APPVERSION="${APPVERSION}" \
      --build-arg HASH="${HASH}" \
      --build-arg TIME="${TIME}" \
      --build-arg TZ="${TZ}" \
      .  -t $NAME
popd
