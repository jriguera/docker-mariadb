#!/bin/bash
set -eo pipefail

host="${MYSQL_ROOT_HOST:-127.0.0.1}"
user="${MYSQL_USER:-root}"
pass="${MYSQL_PASSWORD:-${MYSQL_ROOT_PASSWORD:-$(<${DATADIR}/root.password)}}"

args=(
	# force mysql to not use the local "mysqld.sock" (test "external" connectibility)
	-h"$host"
	-u"$user"
	--silent
)

mysqladmin "${args[@]}" ping > /dev/null && exit 0
exit 1

