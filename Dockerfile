# Dockerfile

FROM docker.repository.cloudera.com/cdsw/engine:8

Run apt-get update && \
	apt-get install -y --no-install-recommends \
        freetds-bin \
        krb5-user \
        ldap-utils \
        libffi6 \
        libsasl2-2 \
        libsasl2-modules \
        locales  \
        lsb-release \
        sasl2-bin \
        sqlite3 \
        unixodbc && \ 
	pip3 install apache-airflow