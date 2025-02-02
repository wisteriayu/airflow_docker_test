# Dockerfile

ARG AIRFLOW_VERSION="2.0.1"
ARG AIRFLOW_EXTRAS="async,amazon,celery,cncf.kubernetes,docker,dask,elasticsearch,ftp,grpc,hashicorp,http,ldap,google,microsoft.azure,mysql,sftp,postgres,redis,sendgrid,slack,ssh,statsd,virtualenv"
ARG ADDITIONAL_AIRFLOW_EXTRAS=""
ARG ADDITIONAL_PYTHON_DEPS=""

ARG AIRFLOW_HOME=/opt/airflow
ARG AIRFLOW_UID="50000"
ARG AIRFLOW_GID="50000"

ARG CASS_DRIVER_BUILD_CONCURRENCY="8"

ARG PYTHON_BASE_IMAGE="docker.repository.cloudera.com/cdsw/engine:8"
ARG PYTHON_MAJOR_MINOR_VERSION="3.6"

ARG AIRFLOW_PIP_VERSION=20.3.4

# By default PIP has progress bar but you can disable it.
ARG PIP_PROGRESS_BAR="on"

##############################################################################################
# This is the build image where we build all dependencies
##############################################################################################
FROM ${PYTHON_BASE_IMAGE} as airflow-build-image
SHELL ["/bin/bash", "-o", "pipefail", "-e", "-u", "-x", "-c"]
# RUN echo 'alias pip="pip3"' >> ~/.bashrc

ARG PYTHON_BASE_IMAGE
ENV PYTHON_BASE_IMAGE=${PYTHON_BASE_IMAGE}

ARG PYTHON_MAJOR_MINOR_VERSION
ENV PYTHON_MAJOR_MINOR_VERSION=${PYTHON_MAJOR_MINOR_VERSION}

# Make sure noninteractive debian install is used and language variables set
ENV DEBIAN_FRONTEND=noninteractive LANGUAGE=C.UTF-8 LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8 LC_MESSAGES=C.UTF-8

# refresh the ubuntu repositories of cloudera image
COPY sources.list /sources.list

RUN cp /etc/apt/sources.list /etc/apt/sources.list.bk \
 	&& rm /etc/apt/sources.list \
	&& cp /sources.list /etc/apt/sources.list \
	&& rm /sources.list

# Install curl and gnupg2 - needed for many other installation steps
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
           curl \
           gnupg2 \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG DEV_APT_DEPS="\
     apt-transport-https \
     apt-utils \
     build-essential \
     ca-certificates \
     gnupg \
     dirmngr \
     freetds-bin \
     freetds-dev \
     gosu \
     krb5-user \
     ldap-utils \
     libffi-dev \
     libkrb5-dev \
     libldap2-dev \
     libpq-dev \
     libsasl2-2 \
     libsasl2-dev \
     libsasl2-modules \
     libssl-dev \
     locales  \
     lsb-release \
     nodejs \
     openssh-client \
     postgresql-client \
     python-selinux \
     sasl2-bin \
     software-properties-common \
     sqlite3 \
     sudo \
     unixodbc \
     unixodbc-dev \
     yarn"
ENV DEV_APT_DEPS=${DEV_APT_DEPS}

ARG ADDITIONAL_DEV_APT_DEPS="libsqlite3-dev"
ENV ADDITIONAL_DEV_APT_DEPS=${ADDITIONAL_DEV_APT_DEPS}

ARG DEV_APT_COMMAND="\
    curl --fail --location https://deb.nodesource.com/setup_10.x | bash - \
    && curl https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - > /dev/null \
    && echo 'deb https://dl.yarnpkg.com/debian/ stable main' > /etc/apt/sources.list.d/yarn.list"
ENV DEV_APT_COMMAND=${DEV_APT_COMMAND}

ARG ADDITIONAL_DEV_APT_COMMAND="echo"
ENV ADDITIONAL_DEV_APT_COMMAND=${ADDITIONAL_DEV_APT_COMMAND}

ARG ADDITIONAL_DEV_APT_ENV=""

# Note missing man directories on debian-buster
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=863199
# Install basic and additional apt dependencies
RUN mkdir -pv /usr/share/man/man1 \
    && mkdir -pv /usr/share/man/man7 \
    && export ${ADDITIONAL_DEV_APT_ENV?} \
    && bash -o pipefail -e -u -x -c "${DEV_APT_COMMAND}" \
    && bash -o pipefail -e -u -x -c "${ADDITIONAL_DEV_APT_COMMAND}" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
           ${DEV_APT_DEPS} \
           ${ADDITIONAL_DEV_APT_DEPS} \
    && apt-get upgrade -y \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG INSTALL_MYSQL_CLIENT="true"
ENV INSTALL_MYSQL_CLIENT=${INSTALL_MYSQL_CLIENT}

# Only copy install_mysql.sh to not invalidate cache on other script changes
COPY scripts/docker/install_mysql.sh /scripts/docker/install_mysql.sh
COPY docker-context-files /docker-context-files
# fix permission issue in Azure DevOps when running the script
# RUN bash /scripts/docker/install_mysql.sh dev

ARG AIRFLOW_REPO=apache/airflow
ENV AIRFLOW_REPO=${AIRFLOW_REPO}

ARG AIRFLOW_BRANCH=master
ENV AIRFLOW_BRANCH=${AIRFLOW_BRANCH}

ARG AIRFLOW_EXTRAS
ARG ADDITIONAL_AIRFLOW_EXTRAS=""
ENV AIRFLOW_EXTRAS=${AIRFLOW_EXTRAS}${ADDITIONAL_AIRFLOW_EXTRAS:+,}${ADDITIONAL_AIRFLOW_EXTRAS}

# Allows to override constraints source
ARG CONSTRAINTS_GITHUB_REPOSITORY="apache/airflow"
ENV CONSTRAINTS_GITHUB_REPOSITORY=${CONSTRAINTS_GITHUB_REPOSITORY}

ARG AIRFLOW_CONSTRAINTS_REFERENCE="constraints-master"
ARG AIRFLOW_CONSTRAINTS="constraints"
ARG AIRFLOW_CONSTRAINTS_LOCATION="https://raw.githubusercontent.com/${CONSTRAINTS_GITHUB_REPOSITORY}/${AIRFLOW_CONSTRAINTS_REFERENCE}/${AIRFLOW_CONSTRAINTS}-${PYTHON_MAJOR_MINOR_VERSION}.txt"
ENV AIRFLOW_CONSTRAINTS_LOCATION=${AIRFLOW_CONSTRAINTS_LOCATION}

ENV PATH=${PATH}:/root/.local/bin
RUN mkdir -p /root/.local/bin

RUN if [[ -f /docker-context-files/.pypirc ]]; then \
        cp /docker-context-files/.pypirc /root/.pypirc; \
    fi

ARG AIRFLOW_PIP_VERSION
ENV AIRFLOW_PIP_VERSION=${AIRFLOW_PIP_VERSION}

# By default PIP has progress bar but you can disable it.
ARG PIP_PROGRESS_BAR
ENV PIP_PROGRESS_BAR=${PIP_PROGRESS_BAR}

# Install Airflow with "--user" flag, so that we can copy the whole .local folder to the final image
# from the build image and always in non-editable mode
ENV AIRFLOW_INSTALL_USER_FLAG="--user"
ENV AIRFLOW_INSTALL_EDITABLE_FLAG=""

# Upgrade to specific PIP version
# RUN pip3 install --no-cache-dir --upgrade "pip==${AIRFLOW_PIP_VERSION}"
# fix pip
# COPY /resources/pip-19.3.1-py2.py3-none-any.whl python3_package/
# RUN pip install --no-index python3_package/pip-19.3.1-py2.py3-none-any.whl && \
#     ln -fs /usr/local/bin/pip3.6 /usr/local/bin/pip3 && \
#     ln -fs /usr/local/bin/pip3.6 /usr/bin/pip3


# By default we do not use pre-cached packages, but in CI/Breeze environment we override this to speed up
# builds in case setup.py/setup.cfg changed. This is pure optimisation of CI/Breeze builds.
ARG AIRFLOW_PRE_CACHED_PIP_PACKAGES="false"
ENV AIRFLOW_PRE_CACHED_PIP_PACKAGES=${AIRFLOW_PRE_CACHED_PIP_PACKAGES}

# By default we install providers from PyPI but in case of Breeze build we want to install providers
# from local sources without the need of preparing provider packages upfront. This value is
# automatically overridden by Breeze scripts.
ARG INSTALL_PROVIDERS_FROM_SOURCES="false"
ENV INSTALL_PROVIDERS_FROM_SOURCES=${INSTALL_PROVIDERS_FROM_SOURCES}

# Only copy install_airflow_from_branch_tip.sh to not invalidate cache on other script changes
COPY scripts/docker/install_airflow_from_branch_tip.sh /scripts/docker/install_airflow_from_branch_tip.sh

# By default we do not upgrade to latest dependencies
ARG UPGRADE_TO_NEWER_DEPENDENCIES="false"
ENV UPGRADE_TO_NEWER_DEPENDENCIES=${UPGRADE_TO_NEWER_DEPENDENCIES}

# In case of Production build image segment we want to pre-install master version of airflow
# dependencies from GitHub so that we do not have to always reinstall it from the scratch.
# The Airflow (and providers in case INSTALL_PROVIDERS_FROM_SOURCES is "false")
# are uninstalled, only dependencies remain
# the cache is only used when "upgrade to newer dependencies" is not set to automatically
# account for removed dependencies (we do not install them in the first place)
RUN if [[ ${AIRFLOW_PRE_CACHED_PIP_PACKAGES} == "true" && \
          ${UPGRADE_TO_NEWER_DEPENDENCIES} == "false" ]]; then \
        bash /scripts/docker/install_airflow_from_branch_tip.sh; \
    fi

# By default we install latest airflow from PyPI so we do not need to copy sources of Airflow
# but in case of breeze/CI builds we use latest sources and we override those
# those SOURCES_FROM/TO with "." and "/opt/airflow" respectively
ARG AIRFLOW_SOURCES_FROM="empty"
ENV AIRFLOW_SOURCES_FROM=${AIRFLOW_SOURCES_FROM}

ARG AIRFLOW_SOURCES_TO="/empty"
ENV AIRFLOW_SOURCES_TO=${AIRFLOW_SOURCES_TO}

COPY ${AIRFLOW_SOURCES_FROM} ${AIRFLOW_SOURCES_TO}

ARG CASS_DRIVER_BUILD_CONCURRENCY
ENV CASS_DRIVER_BUILD_CONCURRENCY=${CASS_DRIVER_BUILD_CONCURRENCY}

# This is airflow version that is put in the label of the image build
ARG AIRFLOW_VERSION
ENV AIRFLOW_VERSION=${AIRFLOW_VERSION}

# Add extra python dependencies
ARG ADDITIONAL_PYTHON_DEPS=""
ENV ADDITIONAL_PYTHON_DEPS=${ADDITIONAL_PYTHON_DEPS}

# Determines the way airflow is installed. By default we install airflow from PyPI `apache-airflow` package
# But it also can be `.` from local installation or GitHub URL pointing to specific branch or tag
# Of Airflow. Note That for local source installation you need to have local sources of
# Airflow checked out together with the Dockerfile and AIRFLOW_SOURCES_FROM and AIRFLOW_SOURCES_TO
# set to "." and "/opt/airflow" respectively.
ARG AIRFLOW_INSTALLATION_METHOD="apache-airflow"
ENV AIRFLOW_INSTALLATION_METHOD=${AIRFLOW_INSTALLATION_METHOD}

# By default latest released version of airflow is installed (when empty) but this value can be overridden
# and we can install version according to specification (For example ==2.0.2 or <3.0.0).
ARG AIRFLOW_VERSION_SPECIFICATION="==2.0.1"
ENV AIRFLOW_VERSION_SPECIFICATION=${AIRFLOW_VERSION_SPECIFICATION}

# We can set this value to true in case we want to install .whl .tar.gz packages placed in the
# docker-context-files folder. This can be done for both - additional packages you want to install
# and for airflow as well (you have to set INSTALL_FROM_PYPI to false in this case)
ARG INSTALL_FROM_DOCKER_CONTEXT_FILES=""
ENV INSTALL_FROM_DOCKER_CONTEXT_FILES=${INSTALL_FROM_DOCKER_CONTEXT_FILES}

# By default we install latest airflow from PyPI. You can set it to false if you want to install
# Airflow from the .whl or .tar.gz packages placed in `docker-context-files` folder.
ARG INSTALL_FROM_PYPI="true"
ENV INSTALL_FROM_PYPI=${INSTALL_FROM_PYPI}

# Those are additional constraints that are needed for some extras but we do not want to
# Force them on the main Airflow package.
# * chardet<4 - required to keep snowflake happy
# * urllib3 - required to keep boto3 happy
# * pyjwt<2.0.0: flask-jwt-extended requires it
ARG EAGER_UPGRADE_ADDITIONAL_REQUIREMENTS="chardet<4 urllib3<1.26 pyjwt<2.0.0"

WORKDIR /opt/airflow

ARG CONTINUE_ON_PIP_CHECK_FAILURE="false"

# Copy all install scripts here
COPY scripts/docker/install*.sh /scripts/docker/

# hadolint ignore=SC2086, SC2010
# RUN if [[ ${INSTALL_FROM_PYPI} == "true" ]]; then \
#         bash /scripts/docker/install_airflow.sh; \
#     fi; \
#     if [[ ${INSTALL_FROM_DOCKER_CONTEXT_FILES} == "true" ]]; then \
#         bash /scripts/docker/install_from_docker_context_files.sh; \
#     fi; \
#     if [[ -n "${ADDITIONAL_PYTHON_DEPS}" ]]; then \
#         bash /scripts/docker/install_additional_dependencies.sh; \
#     fi; \
#     find /root/.local/ -name '*.pyc' -print0 | xargs -0 rm -r || true ; \
#     find /root/.local/ -type d -name '__pycache__' -print0 | xargs -0 rm -r || true

RUN echo && \
    echo Installing all packages with constraints and upgrade if needed && \
    echo && \
    pip3 install ${AIRFLOW_INSTALL_USER_FLAG} ${AIRFLOW_INSTALL_EDITABLE_FLAG} \
         "${AIRFLOW_INSTALLATION_METHOD}[${AIRFLOW_EXTRAS}]${AIRFLOW_VERSION_SPECIFICATION}" \
         --constraint "${AIRFLOW_CONSTRAINTS_LOCATION}"

# Copy compile_www_assets.sh install scripts here
COPY scripts/docker/compile_www_assets.sh /scripts/docker/compile_www_assets.sh

RUN bash /scripts/docker/compile_www_assets.sh

# make sure that all directories and files in .local are also group accessible
RUN find /root/.local -executable -print0 | xargs --null chmod g+x && \
    find /root/.local -print0 | xargs --null chmod g+rw


ARG BUILD_ID
ENV BUILD_ID=${BUILD_ID}
ARG COMMIT_SHA
ENV COMMIT_SHA=${COMMIT_SHA}

ARG AIRFLOW_IMAGE_REPOSITORY="https://github.com/apache/airflow"
ARG AIRFLOW_IMAGE_DATE_CREATED

LABEL org.apache.airflow.distro="debian" \
  org.apache.airflow.distro.version="buster" \
  org.apache.airflow.module="airflow" \
  org.apache.airflow.component="airflow" \
  org.apache.airflow.image="airflow-build-image" \
  org.apache.airflow.version="${AIRFLOW_VERSION}" \
  org.apache.airflow.buildImage.buildId=${BUILD_ID} \
  org.apache.airflow.buildImage.commitSha=${COMMIT_SHA} \
  org.opencontainers.image.source=${AIRFLOW_IMAGE_REPOSITORY} \
  org.opencontainers.image.created=${AIRFLOW_IMAGE_DATE_CREATED} \
  org.opencontainers.image.authors="dev@airflow.apache.org" \
  org.opencontainers.image.url="https://airflow.apache.org" \
  org.opencontainers.image.documentation="https://airflow.apache.org/docs/apache-airflow/stable/production-deployment.html" \
  org.opencontainers.image.source="https://github.com/apache/airflow" \
  org.opencontainers.image.version="${AIRFLOW_VERSION}" \
  org.opencontainers.image.revision="${COMMIT_SHA}" \
  org.opencontainers.image.vendor="Apache Software Foundation" \
  org.opencontainers.image.licenses="Apache-2.0" \
  org.opencontainers.image.ref.name="airflow-build-image" \
  org.opencontainers.image.title="Build Image Segment for Production Airflow Image" \
  org.opencontainers.image.description="Installed Apache Airflow with build-time dependencies"
