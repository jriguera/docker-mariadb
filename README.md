# docker-mariadb

MariaDB Docker image based on Alpine, multi-arch.

### Develop and test builds

Just type:

```
docker-build.sh
```

### Create final release and publish to Docker Hub

```
create-release.sh
```


# Usage

Given the docker image with name `mariadb` from Github Package Repository:

```
docker pull ghcr.io/jriguera/docker-mariadb/mariadb:latest

# Compatibility with MySQL image
docker run --name db -p 3306:3306 -v $(pwd)/datadir:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=secret -e MYSQL_DATABASE=casa -e MYSQL_USER=jose -e MYSQL_PASSWORD=hola -d ghcr.io/jriguera/docker-mariadb/mariadb:latest

docker exec ghcr.io/jriguera/docker-mariadb/mariadb:latest sh -c 'exec mysqldump --all-databases -uroot -p"secret"' > dump.sql
```

## Variables

See `mariadb.sh` for more details.

```
# Configuration parameters
MARIADB_PORT="${MARIADB_PORT:-${PORT}}"
MARIADB_WAIT_TIMEOUT="${MARIADB_WAIT_TIMEOUT:-600}"
MARIADB_MAX_CONNECTIONS="${MARIADB_MAX_CONNECTIONS:-50}"
MARIADB_ENABLE_LOG_WARNINGS="${MARIADB_ENABLE_LOG_WARNINGS:-9}"
MARIADB_ENABLE_LOG_FILES="${MARIADB_ENABLE_LOG_FILES:-off}"
MARIADB_LONG_QUERY_TIME="${MARIADB_LONG_QUERY_TIME:-5}"
MARIADB_SKIP_SHOW_DATABASE="${MARIADB_SKIP_SHOW_DATABASE:-off}"
MARIADB_PERFORMANCE_SCHEMA="${MARIADB_PERFORMANCE_SCHEMA:-on}"
# Generally, it is unwise to set the query cache to be larger than 64-128M
# as the costs associated with maintaining the cache outweigh the performance
# gains.
# The query cache is a well known bottleneck that can be seen even when
# concurrency is moderate. The best option is to disable it from day 1
# by setting query_cache_size = 0 (now the default on MySQL 5.6)
# and to use other ways to speed up read queries: good indexing, adding
# replicas to spread the read load or using an external cache.
MARIADB_QUERY_CACHE_TYPE="${MARIADB_QUERY_CACHE_TYPE:-on}"
MARIADB_QUERY_CACHE_SIZE="${MARIADB_QUERY_CACHE_SIZE:-16M}"
# The buffer pool is where data and indexes are cached: having it as large as possible
# will ensure you use memory and not disks for most read operations.
# Typical values are 50..75% of available RAM.
MARIADB_INNODB_BUFFER_POOL_SIZE="${MARIADB_INNODB_BUFFER_POOL_SIZE:-200M}"
# 25% of innodb_buffer_pool_size
MARIADB_INNODB_LOG_FILE_SIZE="${MARIADB_INNODB_LOG_FILE_SIZE:-50M}"
# The default setting of 1 means that InnoDB is fully ACID compliant.
# It is the best value when your primary concern is data safety, for instance on a master.
# However it can have a significant overhead on systems with slow disks because of the
# extra fsyncs that are needed to flush each change to the redo logs.
# Setting it to 2 is a bit less reliable because committed transactions will be
# flushed to the redo logs only once a second, but that can be acceptable on some situations
# for a master and that is definitely a good value for a replica. 0 is even faster
# but you are more likely to lose some data in case of a crash: it is only a good value for a replica.
MARIADB_ACID_COMPLIANCE_LEVEL="${MARIADB_ACID_COMPLIANCE_LEVEL:-2}"
MARIADB_INITDB_SKIP_TZINFO="false"
# List of plugins to load
MARIADB_PLUGINS_LIST=(${MARIADB_PLUGINS:-})

# Databases and users
# Compatibility with MySQL
MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}"
MARIADB_ROOT_HOST="${MARIADB_ROOT_HOST:-${MYSQL_ROOT_HOST:-localhost}}"
[[ -n "${MYSQL_DATABASE}" ]] && MARIADB_DATABASE="${MYSQL_DATABASE}:${MYSQL_USER:-${MYSQL_DATABASE}}:${MYSQL_PASSWORD:-${MYSQL_DATABASE}}"
# One database db:user:pass
MARIADB_DATABASE=${MARIADB_DATABASE:-}
# List of databases b:user:pass space separated
MARIADB_DATABASES_LIST=(${MARIADB_DATABASES:-${MARIADB_DATABASE}})
```

# Author

Jose Riguera `<jriguera@gmail.com>`

