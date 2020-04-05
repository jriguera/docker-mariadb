# MariaDB docker

# docker build . -t mariadb
# docker run --name db -p 3306:3306 -v $(pwd)/datadir:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=secret -e MYSQL_DATABASE=casa -e MYSQL_USER=jose -e MYSQL_PASSWORD=hola -d mariadb
# docker exec mariadb sh -c 'exec mysqldump --all-databases -uroot -p"secret"' > dump.sql

ARG ARCH=arm32v6
FROM "${ARCH}/alpine:3.11"

ARG VERSION=10.4
ARG MYVERSION=jose2
ARG DATADIR=/var/lib/mysql
ARG PORT=3306
ARG UID=1000
ARG GUID=1000
ARG TZ=Europe/Amsterdam
ARG ARCH

LABEL org.label-schema.description="MariaDB Docker image based on Alpine for the Raspberry Pi."
LABEL org.label-schema.name="rpi-mariadb"
LABEL org.label-schema.version="${VERSION}-${MYVERSION}"
LABEL org.label-schema.usage="/README.md"
LABEL org.label-schema.url="https://hub.docker.com/r/jriguera/rpi-mariadb"
LABEL org.label-schema.vcs-url="https://github.com/jriguera/docker-rpi-mariadb"
LABEL maintainer="Jose Riguera <jriguera@gmail.com>"
LABEL architecture="${ARCH}"

ENV LANG=en_US.utf8
ENV LC_ALL=C.UTF-8
ENV PORT="${PORT}"
ENV DATADIR="${DATADIR}"

RUN set -xe                                                                 && \
    addgroup -g "${GUID}" mysql                                             && \
    adduser -h "${DATADIR}" -D -G mysql -s /sbin/nologin -u "${UID}" mysql  && \
    # Installing Alpine packages
    apk -U upgrade                                                          && \
    apk add --no-cache \
        mariadb~${VERSION} \
        mariadb-client \
        pwgen \
        su-exec \
        tzdata \
        socat \
        net-tools \
        curl \
        bash \
                                                                            && \
    # Timezone
    cp "/usr/share/zoneinfo/${TZ}" /etc/localtime                           && \
    echo "${TZ}" > /etc/timezone                                            && \
    # clean up
    rm -rf /var/lib/mysql/* /etc/mysql/* /etc/my.cnf*                       && \
    rm -rf /tmp/* /var/tmp/* /var/cache/apk/* /var/cache/distfiles/*


COPY *.sh /usr/local/bin/
COPY etc/my.cnf /etc/mysql/

RUN \
    chmod a+x /usr/local/bin/*                                              && \
    ln -s /usr/local/bin/mysql.sh /usr/local/bin/docker-entrypoint.sh       && \
    ln -s /usr/local/bin/mysql.sh /docker-entrypoint.sh                     && \
    ln -s /usr/local/bin/mysql.sh /run.sh                                   && \
    ln -s /usr/local/bin/healhcheck.sh /healhcheck.sh                       && \
    mkdir -p /docker-entrypoint-initdb.d                                    && \
    mkdir -p /var/run/mysqld                                                && \
    mkdir -p /etc/mysql/conf.d                                              && \
    chmod 755 /etc/mysql/conf.d                                             && \
    chown mysql:mysql /var/run/mysqld

VOLUME "${DATADIR}"
EXPOSE "${PORT}"
HEALTHCHECK --interval=1m --timeout=3s --start-period=5m \
    CMD /healthcheck.sh

ENTRYPOINT ["/run.sh"]
# Define default command
CMD ["mysqld", "--debug-gdb"]

