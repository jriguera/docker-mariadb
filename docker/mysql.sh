#!/bin/bash
set -eo pipefail
shopt -s nullglob

# if command starts with an option, prepend mysqld
if [ "${1:0:1}" == '-' ]
then
	set -- mysqld "$@"
fi

# skip setup if they want an option that stops mysqld
HELP=0
for arg
do
	case "$arg" in
		-'?'|--help|--print-defaults|-V|--version)
			HELP=1
			break
			;;
	esac
done

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="${1}"
	local def="${2:-}"

	local fvar="${var}_FILE"
	local val="${def}"

	if [ -n "${!var:-}" ] && [ -r "${fvar}" ]
	then
		echo "* Warning: both ${var} and ${fvar} are set, env ${var} takes priority"
	fi
	if [ -n "${!var:-}" ]
	then
		val="${!var}"
	elif [ -r "${fvar}" ]
	then
		val=$(< "${fvar}")
	fi
	export "${var}"="${val}"
}

_check_config() {
	local run=( "$@" --verbose --help --log-bin-index="$(mktemp -u)" )
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

# Fetch value from server config
# We use mysqld --verbose --help instead of my_print_defaults because the
# latter only show values present in config files, and not server defaults
_get_config() {
	local conf="${1}"
	shift

	"$@" --verbose --help --log-bin-index="$(mktemp -u)" 2>/dev/null | awk '$1 == "'"${conf}"'" { print $2; exit }'
}

# allow the container to be started with `--user`
if [ "${1}" == "mysqld" -a "${HELP}" == "0" -a "$(id -u)" == "0" ]
then
	_check_config "$@"
	DATADIR="$(_get_config 'datadir' "$@")"
	mkdir -p "$DATADIR"
	chown -R mysql:mysql "$DATADIR"
	exec su-exec mysql "$BASH_SOURCE" "$@"
fi

if [ "${1}" == 'mysqld' -a "${HELP}" == "0" ]
then
	# still need to check config, container may have started with --user
	_check_config "$@"
	# Get config
	DATADIR="$(_get_config 'datadir' "$@")"
	if [ ! -d "$DATADIR/mysql" ]
	then
		file_env 'MYSQL_ROOT_PASSWORD'
		if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]
		then
			echo >&2 'ERROR: database is uninitialized and password option is not specified '
			echo >&2 '       You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD'
			exit 1
		fi

		echo "* Initializing $DATADIR ..."
		mkdir -p "$DATADIR"
		mysql_install_db --skip-test-db --datadir="$DATADIR" > /dev/null

		SOCKET="$(_get_config 'socket' "$@")"
		"$@" --silent-startup --skip-networking --socket="${SOCKET}" &
		pid=$!

		mysql=( mysql --protocol=socket -uroot -hlocalhost --socket="${SOCKET}" )
		for i in {30..0}
		do
			if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null
			then
				break
			fi
			echo '* MySQL init process in progress ...'
			sleep 1
		done
		if [ "$i" == 0 ]
		then
			echo >&2 '* MySQL init process FAILED.'
			exit 1
		fi

		if [ -z "$MYSQL_INITDB_SKIP_TZINFO" ]
		then
			# sed is for https://bugs.mysql.com/bug.php?id=20545
			mysql_tzinfo_to_sql /usr/share/zoneinfo | sed 's/Local time zone must be set--see zic manual page/FCTY/' | "${mysql[@]}" mysql
		fi

		if [ ! -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]
		then
			export MYSQL_ROOT_PASSWORD="$(pwgen -1 32)"
			echo "* Generated ROOT password: $MYSQL_ROOT_PASSWORD"
		fi

		rootgrants=""
		# default root to listen for connections from anywhere
		file_env 'MYSQL_ROOT_HOST' '%'
		if [ ! -z "$MYSQL_ROOT_HOST" -a "$MYSQL_ROOT_HOST" != 'localhost' ]
		then
			# no, we don't care if read finds a terminating character in this heredoc
			# https://unix.stackexchange.com/questions/265149/why-is-set-o-errexit-breaking-this-read-heredoc-expression/265151#265151
			read -r -d '' rootgrants <<-EOSQL || true
				CREATE USER 'root'@'${MYSQL_ROOT_HOST}' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
				GRANT ALL ON *.* TO 'root'@'${MYSQL_ROOT_HOST}' WITH GRANT OPTION ;
			EOSQL
		fi

		"${mysql[@]}" <<-EOSQL
			-- What's done in this file shouldn't be replicated
			--  or products like mysql-fabric won't work
			SET @@SESSION.SQL_LOG_BIN=0;
			DELETE FROM mysql.user WHERE user NOT IN ('mysql.sys', 'mysqlxsys', 'root') OR host NOT IN ('localhost') ;
			SET PASSWORD FOR 'root'@'localhost'=PASSWORD('${MYSQL_ROOT_PASSWORD}') ;
			GRANT ALL ON *.* TO 'root'@'localhost' WITH GRANT OPTION ;
			${rootgrants}
			DROP DATABASE IF EXISTS test ;
			FLUSH PRIVILEGES ;
		EOSQL

		if [ ! -z "$MYSQL_ROOT_PASSWORD" ]
		then
			mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
		fi

		file_env 'MYSQL_DATABASE'
		if [ "$MYSQL_DATABASE" ]
		then
			echo "* Generating database $MYSQL_DATABASE if not exists ..."
			echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | "${mysql[@]}"
			mysql+=( "$MYSQL_DATABASE" )
		fi

		file_env 'MYSQL_USER'
		file_env 'MYSQL_PASSWORD'
		if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]
		then
			echo "* Creating user $MYSQL_USER and grant access to database $MYSQL_DATABASE ..."
			echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' ;" | "${mysql[@]}"
			[ -n "$MYSQL_DATABASE" ] && echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%' ;" | "${mysql[@]}"
			echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
		fi

		for f in /docker-entrypoint-initdb.d/*
		do
			case "${f}" in
				*.sh)
					echo "${0}: Running ${f} ..."
					( . "${f}" )
				;;
				*.sql)
					echo "${0}: Loading SQL from ${f} ..."
					"${mysql[@]}" < "${f}"
					echo
				;;
				*.sql.gz)
					echo "${0}: Loading gziped SQL from ${f} ..."
					gunzip -c "${f}" | "${mysql[@]}"
					echo
				;;
				*)
					echo "${0}: Ignoring ${f} ..."
				;;
			esac
		done

		if ! kill -s TERM ${pid} || ! wait ${pid}
		then
			echo >&2 '* MySQL init process FAILED.'
			exit 1
		fi

		echo '* MySQL init process DONE. Ready for start up.'
		echo
	fi
fi

exec "$@"

