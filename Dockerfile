FROM arm32v6/alpine:3.8

# docker build . -t mariadb
# docker run --name db -p 3306:3306 -v $(pwd)/datadir:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=secret -e MYSQL_DATABASE=casa -e MYSQL_USER=jose -e MYSQL_PASSWORD=hola -d mariadb
# docker exec mariadb sh -c 'exec mysqldump --all-databases -uroot -p"secret"' > dump.sql

ARG VERSION=10.2
ARG MYVERSION=jose1
ARG DATADIR=/var/lib/mysql
ARG PORT=3306
ARG UID=1000
ARG GUID=1000
ARG TIMEZONE=Europe/Amsterdam

LABEL org.label-schema.description="MariaDB Docker image based on Alpine for the Raspberry Pi."
LABEL org.label-schema.name="rpi-mariadb"
LABEL org.label-schema.version="${VERSION}-${MYVERSION}"
LABEL org.label-schema.usage="/README.md"
LABEL org.label-schema.url="https://hub.docker.com/r/jriguera/rpi-mariadb"
LABEL org.label-schema.vcs-url="https://github.com/jriguera/docker-rpi-mariadb"
LABEL maintainer="Jose Riguera <jriguera@gmail.com>"
LABEL architecture="ARM32v7/armhf"

ENV LANG=en_US.utf8
ENV LC_ALL=C.UTF-8
ENV MYSQL_PORT="${PORT}"
ENV MYSQL_DATADIR="${DATADIR}"

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
    cp "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime                     && \
    echo "${TIMEZONE}" > /etc/timezone                                      && \
    # clean up
    rm -rf /tmp/* /var/tmp/* /var/cache/apk/* /var/cache/distfiles/* /var/lib/mysql/* /etc/mysql/*


COPY *.sh /usr/local/bin/
COPY etc/my.cnf /etc/mysql/

RUN \
    chmod a+x /usr/local/bin/*                                              && \
    ln -s /usr/local/bin/mysql.sh /usr/local/bin/docker-entrypoint.sh       && \
    ln -s /usr/local/bin/mysql.sh /docker-entrypoint.sh                     && \
    ln -s /usr/local/bin/mysql.sh /run.sh                                   && \
    mkdir -p /docker-entrypoint-initdb.d                                    && \
    mkdir -p /var/run/mysqld                                                && \
    mkdir -p /etc/mysql/conf.d                                              && \
    chmod 755 /etc/mysql/conf.d                                             && \
    chown mysql:mysql /var/run/mysqld

VOLUME "${DATADIR}"
EXPOSE "${PORT}"

ENTRYPOINT ["/run.sh"]
# Define default command
CMD ["mysqld"]
