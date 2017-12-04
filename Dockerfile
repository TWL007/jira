FROM debian:stretch
MAINTAINER Lei Xue<carmark.dlut@gmail.com>

RUN set -ex; \
    if ! command -v gpg > /dev/null; then \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            gnupg \
            dirmngr \
        ; \
        rm -rf /var/lib/apt/lists/*; \
    fi

# explicitly set user/group IDs
RUN groupadd -r jira --gid=999 && useradd -r -g jira --uid=999 -d /home/jira -m jira 

# Note that you also need to update buildscripts/release.sh when the
# Jira version changes
ARG JIRA_VERSION=7.6.0
ARG JIRA_PRODUCT=jira-software
# Permissions, set the linux user id and group id
ARG CONTAINER_UID=999
ARG CONTAINER_GID=999
# Image Build Date By Buildsystem
ARG BUILD_DATE=undefined
# Language Settings
ARG LANG_LANGUAGE=en
ARG LANG_COUNTRY=US

ENV JIRA_USER=jira                            \
    JIRA_GROUP=jira                           \
    JIRA_CONTEXT_PATH=ROOT                    \
    JIRA_HOME=/var/atlassian/jira             \
    JIRA_INSTALL=/opt/jira                    \
    JIRA_SCRIPTS=/usr/local/share/atlassian   \
    MYSQL_DRIVER_VERSION=5.1.44               \
    DOCKERIZE_VERSION=v0.4.0
ENV JAVA_HOME=$JIRA_INSTALL/jre

ENV PATH=$PATH:$JAVA_HOME/bin \
    LANG=${LANG_LANGUAGE}_${LANG_COUNTRY}.UTF-8

COPY imagescripts ${JIRA_SCRIPTS}
# grab gosu for easy step-down from root
ENV GOSU_VERSION 1.10
RUN set -x \
    && apt-get update && apt-get install -y --no-install-recommends ca-certificates wget && rm -rf /var/lib/apt/lists/* \
    && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
    && wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
    && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
    && rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc \
    && chmod +x /usr/local/bin/gosu \
    && gosu nobody true

# make the "en_US.UTF-8" locale so postgres will be utf-8 enabled by default
RUN apt-get update && apt-get install -y locales && rm -rf /var/lib/apt/lists/* \
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.utf8
ENV DOCKERIZE_VERSION v0.6.0

RUN apt-get update && apt-get install -y gzip curl xmlstarlet libc6 libc6-dev libc6-dbg && \
    export JIRA_BIN=atlassian-${JIRA_PRODUCT}-${JIRA_VERSION}-x64.bin && \
    mkdir -p ${JIRA_HOME}                           &&  \
    mkdir -p ${JIRA_INSTALL}                        &&  \
    wget -O /tmp/jira.bin https://downloads.atlassian.com/software/jira/downloads/${JIRA_BIN} && \
    chmod +x /tmp/jira.bin                          &&  \
    /tmp/jira.bin -q -varfile                           \
      ${JIRA_SCRIPTS}/response.varfile              &&  \
    # Install database drivers
    rm -f                                               \
      ${JIRA_INSTALL}/lib/mysql-connector-java*.jar &&  \
    wget -O /tmp/mysql-connector-java-${MYSQL_DRIVER_VERSION}.tar.gz                                              \
      http://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-${MYSQL_DRIVER_VERSION}.tar.gz      &&  \
    tar xzf /tmp/mysql-connector-java-${MYSQL_DRIVER_VERSION}.tar.gz                                              \
      --directory=/tmp                                                                                        &&  \
    cp /tmp/mysql-connector-java-${MYSQL_DRIVER_VERSION}/mysql-connector-java-${MYSQL_DRIVER_VERSION}-bin.jar     \
      ${JIRA_INSTALL}/lib/mysql-connector-java-${MYSQL_DRIVER_VERSION}-bin.jar                                &&  \
    # Add user
    # Adding letsencrypt-ca to truststore
    export KEYSTORE=$JAVA_HOME/lib/security/cacerts && \
    wget -P /tmp/ https://letsencrypt.org/certs/letsencryptauthorityx1.der && \
    wget -P /tmp/ https://letsencrypt.org/certs/letsencryptauthorityx2.der && \
    wget -P /tmp/ https://letsencrypt.org/certs/lets-encrypt-x1-cross-signed.der && \
    wget -P /tmp/ https://letsencrypt.org/certs/lets-encrypt-x2-cross-signed.der && \
    wget -P /tmp/ https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.der && \
    wget -P /tmp/ https://letsencrypt.org/certs/lets-encrypt-x4-cross-signed.der && \
    keytool -trustcacerts -keystore $KEYSTORE -storepass changeit -noprompt -importcert -alias isrgrootx1 -file /tmp/letsencryptauthorityx1.der && \
    keytool -trustcacerts -keystore $KEYSTORE -storepass changeit -noprompt -importcert -alias isrgrootx2 -file /tmp/letsencryptauthorityx2.der && \
    keytool -trustcacerts -keystore $KEYSTORE -storepass changeit -noprompt -importcert -alias letsencryptauthorityx1 -file /tmp/lets-encrypt-x1-cross-signed.der && \
    keytool -trustcacerts -keystore $KEYSTORE -storepass changeit -noprompt -importcert -alias letsencryptauthorityx2 -file /tmp/lets-encrypt-x2-cross-signed.der && \
    keytool -trustcacerts -keystore $KEYSTORE -storepass changeit -noprompt -importcert -alias letsencryptauthorityx3 -file /tmp/lets-encrypt-x3-cross-signed.der && \
    keytool -trustcacerts -keystore $KEYSTORE -storepass changeit -noprompt -importcert -alias letsencryptauthorityx4 -file /tmp/lets-encrypt-x4-cross-signed.der && \
    # Install atlassian ssl tool
    wget -O /home/${CONTAINER_USER}/SSLPoke.class https://confluence.atlassian.com/kb/files/779355358/779355357/1/1441897666313/SSLPoke.class && \
    # Clean caches and tmps
    rm -rf /var/cache/apk/*                         &&  \
    rm -rf /tmp/*                                   &&  \
    rm -rf /var/log/*                               && \
    rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz

# Image Metadata
LABEL com.blacklabelops.application.jira.version=$JIRA_PRODUCT-$JIRA_VERSION \
      com.blacklabelops.application.jira.userid=$CONTAINER_UID \
      com.blacklabelops.application.jira.groupid=$CONTAINER_GID \
      com.blacklabelops.image.builddate.jira=${BUILD_DATE}

#USER jira
WORKDIR ${JIRA_HOME}
VOLUME ["/var/atlassian/jira"]
EXPOSE 8080
ENTRYPOINT ["/usr/local/share/atlassian/docker-entrypoint.sh"]
CMD ["jira"]
