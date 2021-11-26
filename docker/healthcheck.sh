#!/bin/bash
set -eo pipefail

host="${MYSQL_ROOT_HOST:-127.0.0.1}"
user="${MYSQL_USER:-root}"
pass="${MYSQL_PASSWORD:-${MYSQL_ROOT_PASSWORD:-$(<${DATADIR}/root.password)}}"

mysqladmin -h"$host" -u"$user" -p"$pass"  ping  && exit 0
exit 1

