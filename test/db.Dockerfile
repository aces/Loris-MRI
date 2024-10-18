FROM mariadb:latest

# Copy the SQL schema files and the Raisinbread data from the main LORIS repository.
COPY test/Loris/SQL/*.sql .
COPY test/Loris/raisinbread/instruments/instrument_sql/*.sql ./raisinbread/instruments/
COPY test/Loris/raisinbread/RB_files/*.sql ./raisinbread/

# Usually, MariaDB creates the SQL user and database at runtime. Since we want to embed the
# database in the image, we instead create them manually at build time.
ARG DATABASE_NAME
ARG DATABASE_USER
ARG DATABASE_PASS

# Compile the SQL instructions into a single file that will be sourced by MariaDB.
RUN ( \
        echo "CREATE DATABASE $DATABASE_NAME; USE $DATABASE_NAME;" && \
        echo "CREATE USER '$DATABASE_USER'@'%' IDENTIFIED BY '$DATABASE_PASS';" && \
        echo "GRANT SELECT,INSERT,UPDATE,DELETE,DROP,CREATE TEMPORARY TABLES ON $DATABASE_NAME.* TO '$DATABASE_USER'@'%';" && \
        cat \
        0000-00-00-schema.sql \
        0000-00-01-Modules.sql \
        0000-00-02-Permission.sql \
        0000-00-03-ConfigTables.sql \
        0000-00-04-Help.sql \
        0000-00-05-ElectrophysiologyTables.sql \
        raisinbread/instruments/*.sql \
        raisinbread/*.sql \
    ) > source.sql

# Copy the LORIS-MRI database installation script and add it to the compiled SQL file.
COPY install/install_database.sql /tmp/install_database.sql
RUN echo "SET @email := 'root@localhost'; SET @project := 'loris'; SET @minc_dir = '/opt/minc/1.9.18';" >> source.sql
RUN cat /tmp/install_database.sql >> /docker-entrypoint-initdb.d/source.sql

# By default, MariaDB runs the SQL files provided by the user at the time of the first startup of
# the image. However, we want to populate the database at build time, we therefore need to manually
# initialize the database and source the SQL files.
RUN mariadb-install-db
RUN docker-entrypoint.sh mariadbd & \
    sleep 15 && \
    mariadb < source.sql && \
    killall mariadbd
