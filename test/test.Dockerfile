FROM mariadb:latest

RUN echo "CREATE DATABASE testtest;" >> /docker-entrypoint-initdb.d/test-init.sql

# By default, MariaDB runs any scripts in /docker-entrypoint-initdb.d/ at the time of the first
# startup to initialize the database.
# We run those scripts at build time so that the database is populated and part of the final image.
RUN mariadb-install-db

RUN docker-entrypoint.sh mariadbd & \
    sleep 30 && \
    mariadb < /docker-entrypoint-initdb.d/test-init.sql && \
    killall mariadbd
