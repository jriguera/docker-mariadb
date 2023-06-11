#!/usr/bin/env bash

MARIADB_RUNDIR="${C_RUNDIR:-/run/mysqld}"
MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}"
MARIADB_ROOT_HOST="${MARIADB_ROOT_HOST:-${MYSQL_ROOT_HOST:-localhost}}"
MARIADB_SOCKET="${MARIADB_RUNDIR}/mysqld.sock"
MARIADB_USER="${MARIADB_USER:-root}"

exec mysqladmin --protocol=socket --socket=${MARIADB_SOCKET}  ping

