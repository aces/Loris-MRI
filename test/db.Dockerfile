FROM mariadb:latest

COPY test/database/SQL/0000-00-00-schema.sql /0000-00-00-schema.sql
COPY test/database/SQL/0000-00-01-Modules.sql /0000-00-01-Modules.sql
COPY test/database/SQL/0000-00-02-Permission.sql /0000-00-02-Permission.sql
COPY test/database/SQL/0000-00-03-ConfigTables.sql /0000-00-03-ConfigTables.sql
COPY test/database/SQL/0000-00-04-Help.sql /0000-00-04-Help.sql
COPY test/database/SQL/0000-00-05-ElectrophysiologyTables.sql /0000-00-05-ElectrophysiologyTables.sql
COPY test/database/raisinbread/RB_files/*.sql /RB_files/
COPY test/database/raisinbread/instruments/instrument_sql/aosi.sql  /aosi.sql
COPY test/database/raisinbread/instruments/instrument_sql/bmi.sql  /bmi.sql
COPY test/database/raisinbread/instruments/instrument_sql/medical_history.sql  /medical_history.sql
COPY test/database/raisinbread/instruments/instrument_sql/mri_parameter_form.sql  /mri_parameter_form.sql
COPY test/database/raisinbread/instruments/instrument_sql/radiology_review.sql  /radiology_review.sql
COPY test/database/test/test_instrument/testtest.sql /test_instrument.sql

RUN echo "CREATE DATABASE LorisTest; USE LorisTest;" | cat - \
    0000-00-00-schema.sql \
    0000-00-01-Modules.sql \
    0000-00-02-Permission.sql \
    0000-00-03-ConfigTables.sql \
    0000-00-04-Help.sql \
    0000-00-05-ElectrophysiologyTables.sql \
    aosi.sql \
    bmi.sql \
    medical_history.sql \
    mri_parameter_form.sql \
    radiology_review.sql \
    test_instrument.sql \
    RB_files/*.sql > /docker-entrypoint-initdb.d/0000-compiled.sql

RUN echo "CREATE USER 'SQLTestUser'@'%' IDENTIFIED BY 'TestPassword';" >> /docker-entrypoint-initdb.d/0000-compiled.sql
RUN echo "CREATE USER 'SQLTestUser'@'localhost' IDENTIFIED BY 'TestPassword';" >> /docker-entrypoint-initdb.d/0000-compiled.sql
RUN echo "GRANT SELECT,INSERT,UPDATE,DELETE,DROP,CREATE TEMPORARY TABLES ON LorisTest.* TO 'SQLTestUser'@'%';" >> /docker-entrypoint-initdb.d/0000-compiled.sql

# Run the LORIS-MRI database installation script
COPY install/install_database.sql /tmp/install_database.sql
RUN echo "SET @email := 'root@localhost'; SET @project := 'loris'; SET @minc_dir = '/opt/minc/1.9.18';" >> 0000-compiled.sql
RUN cat /tmp/install_database.sql >> /docker-entrypoint-initdb.d/0000-compiled.sql

# By default, MariaDB runs the scripts in /docker-entrypoint-initdb.d/ at the time of the first
# startup to initialize the database. However, we want to populate the database at build time so
# that the database is part of the final image (and can be cached for CI).
RUN mariadb-install-db
RUN docker-entrypoint.sh mariadbd & \
    sleep 30 && \
    mariadb < /docker-entrypoint-initdb.d/0000-compiled.sql && \
    killall mariadbd

CMD ["mariadbd", "--user=root"]
