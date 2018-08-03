# docker-rpi-mariadb

MariaDB Docker image based on Alpine for the Raspberry Pi.

### Develop and test builds

Just type:

```
docker build . -t mariadb
```

### Create final release and publish to Docker Hub

```
create-release.sh
```


### Run

Given the docker image with name `mariadb`:

```
docker pull jriguera/mariadb:10.2-jose0

docker run --name db -p 3306:3306 -v $(pwd)/datadir:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=secret -e MYSQL_DATABASE=casa -e MYSQL_USER=jose -e MYSQL_PASSWORD=hola -d jriguera/mariadb

docker exec jriguera/mariadb sh -c 'exec mysqldump --all-databases -uroot -p"secret"' > dump.sql
```

# Author

Jose Riguera `<jriguera@gmail.com>`

