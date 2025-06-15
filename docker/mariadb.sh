#!/usr/bin/env bash
set -eo pipefail
shopt -s nullglob
[[ ${DEBUG} =~ (true|1|yes) ]] && set -x

# Defined in the Dockerfile but
# if undefined, populate environment variables with sane defaults
MARIADB_DATADIR="${C_DATADIR:-/var/lib/mysql}"
MARIADB_ETCDIR="${C_ETCDIR:-/etc/mysql}"
MARIADB_CONFIGDIR="${C_CONFIGDIR:-/config}"
MARIADB_USER="${C_USERNAME:-mysql}"
MARIADB_GROUP="${C_GROUPNAME:-mysql}"
MARIADB_RUNDIR="${C_RUNDIR:-/run/mysqld}"
MARIADB_TEMPLATE_CONFIG="${MARIADB_ETCDIR}/my.cnf.template"

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

# Usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
    local var="${1}"
    local def="${2:-}"

    local fvar="${C_CONFIGDIR}/${var}_FILE"
    local val="${def}"
    if [[ -n "${!var:-}" ]] &&  [[ -r "${fvar}" ]]
    then
        echo "* Warning: both ${var} and ${fvar} are set, file ${fvar} takes priority"
    fi
    [[ -r "${fvar}" ]] && val=$(< "${fvar}")
    [[ -n "${!var:-}" ]] && val="${!var}"
    export "${var}"="${val}"
}

# Check if the configuration is correct
check_config() {
    local run=("$@" --verbose --help --log-bin-index="$(mktemp -u)")
    if ! errors="$("${run[@]}" 2>&1 >/dev/null)"
    then
        cat >&2 <<-EOM
			ERROR: mysqld failed while attempting to check config
			command was: "${run[*]}"
			$errors
		EOM
        exit 1
    fi
}

# Render a template configuration file
# expand variables + preserve formatting
render_template() {
    local template="${1}"
    local destination="${2}"
    echo "* Generating default configuration from environment variables in ${destination} ..."

    eval "echo \"$(cat ${template})\"" > "${destination}"
}

# Fetch value from server config
# We use mysqld --verbose --help instead of my_print_defaults because the
# latter only show values present in config files, and not server defaults
get_config() {
    local conf="${1}"
    shift
    "$@" --verbose --help --log-bin-index="$(mktemp -u)" 2>/dev/null | \
        awk -v var="^${conf} " '{ if ($0 ~ var) { print $2; exit }}'
}

# Initialize a directory to become MariaDB datadir
# also sets root user credentials
init_datadir() {
    local datadir="${1}"
    local socket="${2}"
    local root_pass="${3}"
    local root_host="${4}"
    shift 4
    local pid
    local rc=0
    local timeout=0
    local rootgrants=""
    local mysqlcli=("mariadb"
        "--protocol=socket"
        "--socket=${socket}"
    )
    local mysqlserver=("$@"
        "--silent-startup"
        "--skip-networking"
        "--skip-name-resolve"
        "--default-time-zone=SYSTEM"
        "--skip-host-cache"
        "--skip-slave-start"
        "--skip-external-locking"
        "--wsrep_on=OFF"
        "--expire-logs-days=0"
        "--loose-innodb_buffer_pool_load_at_startup=0"
        "--loose-innodb_buffer_pool_dump_at_shutdown=0"
        "--socket=${socket}"
    )
    local mysqlinstall=("mariadb-install-db"
        "--cross-bootstrap"
        "--auth-root-authentication-method=socket"
        "--auth-root-socket-user=${MARIADB_USER}"
        "--skip-test-db"
        "--default-time-zone=SYSTEM"
        "--skip-log-bin"
        "--expire-logs-days=0"
        "--loose-innodb_buffer_pool_load_at_startup=0"
        "--loose-innodb_buffer_pool_dump_at_shutdown=0"
        "--datadir=${datadir}"
    )
    echo "* Initializing Datadir at ${datadir} ..."
    ${mysqlinstall[@]}
    # Start ephemeral mariadb server just to create the DB
    { ${mysqlserver[@]} & } && pid=$!
    for timeout in {30..0}
    do
        echo 'SELECT 1' | ${mysqlcli[@]} && break
        echo "* MariaDB init process in progress (${timeout})..."
        sleep 1
    done
    if [[ ${timeout} -eq 0 ]]
    then
        echo '* MariaDB init process FAILED.' >&2
        return 1
    fi
    # TZINFO
    if [[ -z "${MARIADB_INITDB_SKIP_TZINFO}" ]] || [[ ! ${MARIADB_INITDB_SKIP_TZINFO} =~ (true|1|yes) ]]
    then
        mariadb-tzinfo-to-sql --skip-write-binlog /usr/share/zoneinfo | ${mysqlcli[@]} "mysql"
    fi
    # Run
    "${mysqlcli[@]}" <<-EOSQL
		-- What's done in this file shouldn't be replicated
		--  or products like mysql-fabric won't work
		SET @@SESSION.SQL_LOG_BIN=0;
		DELETE FROM mysql.user WHERE user NOT IN ('mysql.sys', 'mysqlxsys', 'root', '${MARIADB_USER}') OR host NOT IN ('localhost') ;
		SET PASSWORD FOR 'root'@'${root_host}'=PASSWORD('${root_pass}') ;
		GRANT ALL ON *.* TO 'root'@'${root_host}' WITH GRANT OPTION ;
		-- Root can login automatically via socket
		GRANT ALL ON *.* TO 'root'@'localhost' IDENTIFIED VIA unix_socket WITH GRANT OPTION ;
		DROP DATABASE IF EXISTS test ;
		FLUSH PRIVILEGES ;
	EOSQL
    rc=$?
    # Stop the ephemeral server
    kill -s TERM ${pid}
    wait ${pid} || echo '* MariaDB init process has FAILED.' >&2
    return ${rc}
}

# Perform upgrade
upgrade() {
    local datadir="${1}"
    local socket="${2}"
    shift 2
    local pid
    local rc=0
    local timeout=0
    local backupfile="backup_dbs_pre_upgrade-$(date +%F_%H-%M-%S)"
    local mysqlcli=("mariadb-upgrade"
        "--protocol=socket"
        "--socket=${socket}"
    )
    local mysqlserver=("$@"
        "--silent-startup"
        "--skip-networking"
        "--skip-grant-tables"
        "--skip-name-resolve"
        "--default-time-zone=SYSTEM"
        "--skip-host-cache"
        "--skip-slave-start"
        "--skip-external-locking"
        "--wsrep_on=OFF"
        "--expire-logs-days=0"
        "--loose-innodb_buffer_pool_load_at_startup=0"
        "--loose-innodb_buffer_pool_dump_at_shutdown=0"
        "--socket=${socket}"
    )
    echo "* Checking if upgrade is needed ..."
    # Start ephemeral mariadb server to perform the upgrade the DB
    { ${mysqlserver[@]} & } && pid=$!
    for timeout in {30..0}
    do
        echo 'SELECT 1' | ${mysqlcli[@]} &>/dev/null && break
        echo "* MariaDB init process in progress (${timeout})..."
        sleep 1
    done
    if [[ ${timeout} -eq 0 ]]
    then
        echo '* MariaDB init process FAILED.' >&2
        return 1
    fi
    rc=0
    if ${mysqlcli[@]} --silent --check-if-upgrade-is-needed
    then
        backup="${datadir}/${backupfile}.sql.zst"
        echo "* Upgrade is needed, performing a backup of all databases to ${backup} ..."
        if ! mariadb-dump \
            --skip-lock-tables \
            --replace \
            --socket="${socket}" \
            --all-databases | zstd > "${backup}"
        then
            echo '* Unable backup database for upgrade.' >&2
            rc=1
        else
            ${mysqlcli[@]} --verbose --debug-check
            rc=$?
        fi
    fi
    # Stop the ephemeral server
    kill -s TERM ${pid}
    wait ${pid} || echo '* MariaDB upgrade process has FAILED.' >&2
    return ${rc}
}

# Initiliaze a DB and load dumps if present
init_database() {
    local -n mysql=${1}
    local datadir="${2}"
    local database="${3}"
    local user="${4}"
    local password="${5}"

    local dumps=()

    # Create the database. Do a check to see if the DB is there is faster
    if [[ ! -d "${datadir}/${database}" ]]
    then
        echo "* Generating database '${database}' if not exists ..."
        ${mysql[@]} <<-EOSQL
			CREATE DATABASE IF NOT EXISTS \`${database}\` CHARACTER SET utf8 COLLATE utf8_general_ci;
		EOSQL
        if [[ -n "${user}" ]] && [[ -n "${password}" ]]
        then
            echo "* Creating user ${user} and grant access to database ${database} ..."
            ${mysql[@]} "${database}" <<-EOSQL
				CREATE USER '${user}'@'%' IDENTIFIED BY '${password}' ;
				GRANT ALL ON \`${database}\`.* TO '${user}'@'%';
				FLUSH PRIVILEGES ;
			EOSQL
        fi
    fi
    if [[ -d "${MARIADB_CONFIGDIR}/${database}" ]]
    then
        echo "* Trying to load database DB dumps in ${MARIADB_CONFIGDIR}/${database}"
        while IFS=  read -r -d $'\0' line
        do
            dumps+=("${line}")
        done < <(find -L "${MARIADB_CONFIGDIR}/${database}" -type f \( -name "*.sql" -o -name "*.sql.gz" \) -print0 | sort -z)
        for f in ${dumps[@]}
        do
            case "${f}" in
                *.sql)
                    echo "* Loading SQL from ${f} ..."
                    ${mysql[@]} "${database}" < "${f}"
                    echo
                ;;
                *.sql.gz)
                    echo "* Loading gziped SQL from ${f} ..."
                    gunzip -c "${f}" | ${mysql[@]} "${database}"
                    echo
                ;;
            esac
        done
    else
        echo "* No database dump found for ${database} in ${MARIADB_CONFIGDIR}/${database}"
    fi
    echo "* MariaDB '${database}' init process is DONE. Ready for start up."
}


## Program

# if command starts with an option, prepend mariadbd
if [[ ${1:0:1} == '-' ]]
then
    # Listen to signals, most importantly CTRL+C
    set -- mariadbd --debug-gdb "$@"
fi

# allow the container to be started with `--user`
if [[ ${1} == 'mariadbd' ]]
then
    if [[ "$(id -u)" == "0" ]]
    then
        mkdir -p "${MARIADB_DATADIR}" "${MARIADB_RUNDIR}" "${MARIADB_ETCDIR}"
        chown -R "${MARIADB_USER}:${MARIADB_GROUP}" "${MARIADB_DATADIR}" "${MARIADB_RUNDIR}" "${MARIADB_ETCDIR}"
        exec su-exec ${MARIADB_USER} "${BASH_SOURCE}" "$@"
    fi
    render_template "${MARIADB_TEMPLATE_CONFIG}" "${MARIADB_ETCDIR}/my.cnf"
    check_config "$@"
    socket="$(get_config 'socket' "$@")"
    datadir="$(get_config 'datadir' "$@")"

    mysqlcli=("mariadb"
        "--protocol=socket"
        "--socket=${socket}"
    )
    mysqlserver=("$@"
        "--silent-startup"
        "--skip-networking"
        "--skip-name-resolve"
        "--default-time-zone=SYSTEM"
        "--skip-host-cache"
        "--skip-slave-start"
        "--skip-external-locking"
        "--wsrep_on=OFF"
        "--expire-logs-days=0"
        "--loose-innodb_buffer_pool_load_at_startup=0"
        "--socket=${socket}"
    )

    if [[ ! -d "${datadir}/mysql" ]]
    then
        file_env 'MARIADB_ROOT_PASSWORD' "$(pwgen -1 32)"
        echo "* MariaDB root password stored in: ${datadir}/root.password"
        echo "${MARIADB_ROOT_PASSWORD}" > "${datadir}/root.password"
        if ! init_datadir "${datadir}" "${socket}" "${MARIADB_ROOT_PASSWORD}" "${MARIADB_ROOT_HOST}" "$@"
        then
            rm -f "${datadir}/root.password"
            exit 1
        fi
    else
        upgrade  "${datadir}" "${socket}" "$@"
    fi
    MARIADB_ROOT_PASSWORD="$(<${datadir}/root.password)"
    [[ -n "${MARIADB_ROOT_PASSWORD}" ]] && mysqlcli+=(-p"${MARIADB_ROOT_PASSWORD}")
    # Start ephemeral mariadb server just to create the DB
    { ${mysqlserver[@]} & } && pid=$!
    for timeout in {120..0}
    do
        echo 'SELECT 1' | ${mysqlcli[@]} && break
        echo "* MariaDB init process in progress (${timeout})..."
        sleep 1
    done
    if [[ ${timeout} -eq 0 ]]
    then
        echo '* MariaDB init process FAILED.' >&2
    else
        for item in ${MARIADB_DATABASES_LIST[@]}
        do
            dbuserpass=(${item//:/ })
            database="${dbuserpass[0]}"
            user="${dbuserpass[1]}"
            password="${dbuserpass[2]}"
            init_database mysqlcli "${datadir}" "${database}" "${user}" "${password}"
        done
        echo "* Trying to load dumps in ${MARIADB_CONFIGDIR} ..."
        dumps=()
        while IFS=  read -r -d $'\0' line
        do
            dumps+=("${line}")
        done < <(find -L ${MARIADB_CONFIGDIR} -type f \( -name "*.sql" -o -name "*.sql.gz" \) -print0 | sort -z)
        for f in ${dumps[@]}
        do
            case "${f}" in
                *.sql)
                    echo "* Loading SQL from ${f} ..."
                    ${mysqlcli[@]} < "${f}" || true
                ;;
                *.sql.gz)
                    echo "* Loading gziped SQL from ${f} ..."
                    gunzip -c "${f}" | ${mysqlcli[@]} || true
                ;;
                *.sql.zst)
                    echo "* Loading zst SQL from ${f} ..."
                    zstd -dc "$f" | ${mysqlcli[@]} || true
                ;;
            esac
        done
    fi
    # Stop the ephemeral server
    kill -s TERM ${pid}
    if ! wait ${pid}
    then
        echo "* MariaDB database import/creation has FAILED." >&2 
        exit 1
    fi
    for f in /docker-entrypoint-initdb.d/*
    do
        case "${f}" in
            *.sh)
                echo "* Running ${f} ..."
                ( . "${f}" )
            ;;
            *)
                echo "* Ignoring ${f} ..."
            ;;
        esac
    done
    echo "* MariaDB server ready to start!"
fi

exec "$@"