# MariaDB docker

# docker build . -t mariadb
# docker run --name db -p 3306:3306 -v $(pwd)/datadir:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=secret -e MYSQL_DATABASE=casa -e MYSQL_USER=jose -e MYSQL_PASSWORD=hola -d mariadb
# docker exec mariadb sh -c 'exec mysqldump --all-databases -uroot -p"secret"' > dump.sql

ARG BASE=alpine:3.18
FROM $BASE

ARG VERSION=1
ARG APPVERSION=10.11
ARG TIME=1970-00-00T00:00:00.00Z
ARG HASH=undefined
ARG REPOSITORY="https://github.com/jriguera/docker-mariadb"

ARG DATADIR=/var/lib/mysql
ARG CONFIGDIR=/config
ARG ETCDIR=/etc/mysql
ARG RUNDIR=/run/mysqld
ARG PORT=3306
ARG UID=1000
ARG GUID=1000
ARG TZ=UTC
ARG USER=mysql
ARG GROUP=mysql

LABEL org.opencontainers.image.title="docker-mariadb"
LABEL org.opencontainers.image.created="${TIME}}"
LABEL org.opencontainers.image.base.name="${BASE}"
LABEL org.opencontainers.image.description="MariaDB packed in a multi-arch container image based on alpine: https://mariadb.org/"
LABEL org.opencontainers.image.authors="Jose Riguera <jriguera@gmail.com>"
LABEL org.opencontainers.image.url="${REPOSITORY}#readme"
LABEL org.opencontainers.image.documentation="${REPOSITORY}#readme"
LABEL org.opencontainers.image.source="${REPOSITORY}"
LABEL org.opencontainers.image.version="${VERSION}-${APPVERSION}}"
LABEL org.opencontainers.image.revision="${HASH}"
LABEL org.opencontainers.image.vendor="jriguera"
LABEL org.opencontainers.image.licenses="GPL-3"
LABEL es.riguera.jose.container.service=mosquitto
LABEL es.riguera.jose.container.port="${PORT}"
LABEL es.riguera.jose.container.version="${VERSION}-${APPVERSION}"
LABEL es.riguera.jose.container.appversion="${APPVERSION}"
LABEL es.riguera.jose.container.repository="${REPOSITORY}"
LABEL es.riguera.jose.container.hash="${HASH}"

ENV C_DATADIR="${DATADIR}"
ENV C_CONFIGDIR="${CONFIGDIR}"
ENV C_ETCDIR="${ETCDIR}"
ENV C_RUNDIR="${RUNDIR}"
ENV C_USERNAME="${USER}"
ENV C_GROUPNAME="${GROUP}"
ENV PORT="${PORT}"
ENV LANG=en_US.utf8
ENV LC_ALL=C.UTF-8

RUN set -xe                                                                            && \
    addgroup -g ${GUID} ${USER}                                                        && \
    adduser -h ${DATADIR} -D -G ${GROUP} -s /sbin/nologin -u ${UID} ${USER}            && \
    # Installing Alpine packages
    apk -U upgrade                                                                     && \
    apk add --no-cache \
        mariadb~${APPVERSION} \
        mariadb-client~${APPVERSION} \
        mariadb-server-utils~${APPVERSION} \
        mariadb-mytop~${APPVERSION} \
        mariadb-common~${APPVERSION} \
        mariadb-backup~${APPVERSION} \
        mariadb-connector-c \
        zstd \
        pwgen \
        su-exec \
        tzdata \
        socat \
        net-tools \
        curl \
        bash \
                                                                                        && \
    # Timezone
    cp "/usr/share/zoneinfo/${TZ}" /etc/localtime                                       && \
    echo ${TZ} > /etc/timezone                                                          && \
    # clean up
    rm -rf ${DATADIR}/* ${ETCDIR} /etc/my.cnf*                                          && \
    rm -rf /tmp/* /var/tmp/* /var/cache/apk/* /var/cache/distfiles/*


COPY *.sh /usr/local/bin/
COPY etc/my.cnf.template "${ETCDIR}/"

RUN \
    chmod a+x /usr/local/bin/*                                              && \
    ln -s /usr/local/bin/mariadb.sh /usr/local/bin/docker-entrypoint.sh     && \
    ln -s /usr/local/bin/mariadb.sh /docker-entrypoint.sh                   && \
    ln -s /usr/local/bin/mariadb.sh /run.sh                                 && \
    ln -s /usr/local/bin/healthcheck.sh /healthcheck.sh                     && \
    mkdir -p /docker-entrypoint-initdb.d                                    && \
    mkdir -p ${RUNDIR} ${CONFIGDIR} "${ETCDIR}/conf.d"                      && \
    chmod 755 ${RUNDIR} ${CONFIGDIR} "${ETCDIR}/conf.d"                     && \
    chown -R "${USER}:${GROUP}" ${RUNDIR} ${CONFIGDIR} ${ETCDIR}

VOLUME "${DATADIR}"
EXPOSE "${PORT}"
HEALTHCHECK --interval=1m --timeout=10s --start-period=5m CMD /healthcheck.sh

ENTRYPOINT ["/run.sh"]
# Define default command
CMD ["mariadbd", "--debug-gdb"]

