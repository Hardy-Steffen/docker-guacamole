FROM library/tomcat:9-jre11

ENV ARCH=amd64 \
  GUAC_VER=1.4.0 \
  GUACAMOLE_HOME=/app/guacamole \
  PG_MAJOR=13 \
  PGDATA=/config/postgres \
  POSTGRES_USER=guacamole \
  POSTGRES_DB=guacamole_db

# Apply the s6-overlay

RUN curl -SLO "https://github.com/just-containers/s6-overlay/releases/download/v3.0.0.2/s6-overlay-x86_64-3.0.0.2.tar.xz" \
  && tar -xzf s6-overlay-x86_64-3.0.0.2.tar.xz -C / \
  && tar -xzf s6-overlay-x86_64-3.0.0.2.tar.xz -C /usr ./bin \
  && rm -rf s6-overlay-x86_64-3.0.0.2.tar.xz \
  && mkdir -p ${GUACAMOLE_HOME} \
    ${GUACAMOLE_HOME}/lib \
    ${GUACAMOLE_HOME}/extensions

WORKDIR ${GUACAMOLE_HOME}

# Install dependencies
RUN apt-get update && apt-get install -y \
    libcairo2-dev libjpeg62-turbo-dev build-essential clang autoconf libtool llvm libpng-dev \
    libossp-uuid-dev libavcodec-dev libavutil-dev \
    libswscale-dev freerdp2-dev libfreerdp-client2-2 libpango1.0-dev \
    libssh2-1-dev libtelnet-dev libvncserver-dev \
    libpulse-dev libssl-dev libvorbis-dev libwebp-dev libwebsockets-dev \
    ghostscript postgresql-${PG_MAJOR} \
  && rm -rf /var/lib/apt/lists/*

# Link FreeRDP to where guac expects it to be
RUN [ "$ARCH" = "armhf" ] && ln -s /usr/local/lib/freerdp /usr/lib/arm-linux-gnueabihf/freerdp || exit 0
RUN [ "$ARCH" = "amd64" ] && ln -s /usr/local/lib/freerdp /usr/lib/x86_64-linux-gnu/freerdp || exit 0

# Install guacamole-server
RUN curl -SLO "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/1.4.0/source/guacamole-server-1.4.0.tar.gz" \
  && tar -xzf guacamole-server-1.4.0.tar.gz \
  && cd guacamole-server-1.4.0 \
  && ./configure --enable-allow-freerdp-snapshots \
  && make -j$(getconf _NPROCESSORS_ONLN) \
  && make install \
  && cd .. \
  && rm -rf guacamole-server-1.4.0.tar.gz guacamole-server-1.4.0 \
  && ldconfig

# Install guacamole-client and postgres auth adapter
RUN set -x \
  && rm -rf ${CATALINA_HOME}/webapps/ROOT \
  && curl -SLo ${CATALINA_HOME}/webapps/ROOT.war "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/1.4.0/binary/guacamole-1.4.0.war" \
  && curl -SLo ${GUACAMOLE_HOME}/lib/postgresql-42.1.4.jar "https://jdbc.postgresql.org/download/postgresql-42.1.4.jar" \
  && curl -SLO "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/1.4.0/binary/guacamole-auth-jdbc-1.4.0.tar.gz" \
  && tar -xzf guacamole-auth-jdbc-1.4.0.tar.gz \
  && cp -R guacamole-auth-jdbc-1.4.0/postgresql/guacamole-auth-jdbc-postgresql-1.4.0.jar ${GUACAMOLE_HOME}/extensions/ \
  && cp -R guacamole-auth-jdbc-1.4.0/postgresql/schema ${GUACAMOLE_HOME}/ \
  && rm -rf guacamole-auth-jdbc-1.4.0 guacamole-auth-jdbc-1.4.0.tar.gz

# Add optional extensions
RUN set -xe \
  && mkdir ${GUACAMOLE_HOME}/extensions-available \
  && for i in auth-ldap auth-duo auth-header auth-cas auth-openid auth-quickconnect auth-totp; do \
    echo "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/1.4.0/binary/guacamole-${i}-1.4.0.tar.gz" \
    && curl -SLO "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/1.4.0/binary/guacamole-${i}-1.4.0.tar.gz" \
    && tar -xzf guacamole-${i}-1.4.0.tar.gz \
    && cp guacamole-${i}-1.4.0/guacamole-${i}-1.4.0.jar ${GUACAMOLE_HOME}/extensions-available/ \
    && rm -rf guacamole-${i}-1.4.0 guacamole-${i}-1.4.0.tar.gz \
  ;done

ENV PATH=/usr/lib/postgresql/${PG_MAJOR}/bin:$PATH
ENV GUACAMOLE_HOME=/config/guacamole

WORKDIR /config

COPY root /

EXPOSE 8080

ENTRYPOINT [ "/init" ]
