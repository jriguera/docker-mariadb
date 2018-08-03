#!/usr/bin/env bash
# set -o pipefail  # exit if pipe command fails
[ -z "$DEBUG" ] || set -x
set -e

##

NAME="mariadb"
DOCKER_TAG="jriguera/$NAME"
RELEASE="rpi-mariadb"
DESCRIPTION="Docker image to run MariaDB in a Raspberry Pi"
GITHUB_REPO="jriguera/docker-rpi-mariadb"

###

DOCKER=docker
JQ=jq
CURL="curl -s"
RE_VERSION_NUMBER='^[0-9]+([0-9\.]*[0-9]+)*$'

###

VERSION=""
case $# in
    0)
        echo "*** Creating a new release. Automatically calculating version number"
        ;;
    1)
        if [ $1 == "-h" ] || [ $1 == "--help" ]
        then
            echo "Usage:  $0 [version-number]"
            echo "  Creates a release, commits the changes to this repository using tags and uploads "
            echo "  the release to Github Releases and the final Docker image to Docker Hub. "
            echo "  It also adds comments based on previous git commits."
            exit 0
        else
            VERSION=$1
            if ! [[ $VERSION =~ $RE_VERSION_NUMBER ]]
            then
                echo "ERROR: Incorrect version number!"
                exit 1
            fi
            echo "*** Creating a new release. Using release version number $VERSION."
        fi
        ;;
    *)
        echo "ERROR: incorrect argument. See '$0 --help'"
        exit 1
        ;;
esac

# Create a personal github token to use this script
if [ -z "$GITHUB_TOKEN" ]
then
    echo "Github TOKEN not defined!"
    echo "See https://help.github.com/articles/creating-an-access-token-for-command-line-use/"
    exit 1
fi

# You need bosh installed and with you credentials
if ! [ -x "$(command -v $DOCKER)" ]
then
    echo "ERROR: $DOCKER command not found! Please install it and make it available in the PATH"
    exit 1
fi

# You need jq installed
if ! [ -x "$(command -v $JQ)" ]
then
    echo "ERROR: $JQ command not found! Please install it and make it available in the PATH"
    exit 1
fi

DOCKER_USER=$(docker info 2> /dev/null  | sed -ne 's/^Username: \(.*\)/\1/p')
if [ -z "$DOCKER_USER" ]
then
    echo "ERROR: Not logged in Docker Hub!"
    echo "Please perform 'docker login' with your credentials in order to push images there."
    exit 1
fi

# Creating the release
if [ -z "$VERSION" ]
then
    VERSION=$(sed -ne 's/^ARG.* VERSION=\(.*\)/\1/p' Dockerfile)
    MYVERSION=$(sed -ne 's/^ARG.* MYVERSION=\(.*\)/\1/p' Dockerfile)
    [ -n "$MYVERSION" ] && VERSION="$VERSION-$MYVERSION"
    echo "* Creating final release version $VERSION (from Dockerfile) ..."
else
    echo "* Creating final release version $VERSION (from input)..."
fi

# Get the last git commit made by this script
LASTCOMMIT=$(git show-ref --tags -d | tail -n 1)
if [ -z "$LASTCOMMIT" ]
then
    echo "* Changes since the beginning: "
    CHANGELOG=$(git log --pretty="%h %aI %s (%an)" | sed 's/^/- /')
else
    echo "* Changes since last version with commit $LASTCOMMIT: "
    CHANGELOG=$(git log --pretty="%h %aI %s (%an)" $LASTCOMMIT..@ | sed 's/^/- /')
fi
if [ -z "$CHANGELOG" ]
then
    echo "ERROR: no commits since last release with commit $LASTCOMMIT!. Please "
    echo "commit your changes to create and publish a new release!"
    exit 1
fi
echo "$CHANGELOG"

echo "* Building Docker image with tag $NAME:$VERSION ..."
$DOCKER build . -t $NAME
$DOCKER tag $NAME $DOCKER_TAG

# Uploading docker image
echo "* Pusing Docker image to Docker Hub ..."
$DOCKER push $DOCKER_TAG
$DOCKER tag $NAME $DOCKER_TAG:$VERSION
$DOCKER push $DOCKER_TAG

# Create annotated tag
echo "* Creating a git tag ... "
git tag -a "v$VERSION" -m "$RELEASE v$VERSION"
git push

# Create a release in Github
echo "* Creating a new release in Github ... "
DESC=$(cat <<EOF
# $RELEASE version $VERSION

$DESCRIPTION

## Changes since last version

$CHANGELOG

## Using it

Given the docker image with name `mariadb`:

    docker pull jriguera/mariadb:10.2-jose0

    docker run --name db -p 3306:3306 -v $(pwd)/datadir:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=secret -e MYSQL_DATABASE=casa -e MYSQL_USER=jose -e MYSQL_PASSWORD=hola -d jriguera/mariadb

    docker exec jriguera/mariadb sh -c 'exec mysqldump --all-databases -uroot -p"secret"' > dump.sql

EOF
)
printf -v DATA '{"tag_name": "v%s","target_commitish": "master","name": "v%s","body": %s,"draft": false, "prerelease": false}' "$VERSION" "$VERSION" "$(echo "$DESC" | $JQ -R -s '@text')"
$CURL -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" -XPOST --data "$DATA" "https://api.github.com/repos/$GITHUB_REPO/releases" > /dev/null

git fetch --tags

echo
echo "*** Description https://github.com/$GITHUB_REPO/releases/tag/v$VERSION: "
echo
echo "$DESC"

exit 0
