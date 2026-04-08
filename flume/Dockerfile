FROM apache/hadoop:3
USER root

# ── Installer wget ────────────────────────────────────────────
RUN yum install -y wget ca-certificates && yum clean all

# ── Télécharger Apache Flume 1.11.0 ──────────────────────────
ENV FLUME_VERSION=1.11.0
RUN wget -q \
    "https://archive.apache.org/dist/flume/${FLUME_VERSION}/apache-flume-${FLUME_VERSION}-bin.tar.gz" \
    -O /tmp/flume.tar.gz && \
    tar -xzf /tmp/flume.tar.gz -C /opt && \
    mv /opt/apache-flume-${FLUME_VERSION}-bin /opt/flume && \
    rm /tmp/flume.tar.gz

ENV FLUME_HOME=/opt/flume
ENV PATH=$PATH:${FLUME_HOME}/bin

# ── Supprimer les JARs Flume qui entrent en conflit avec Hadoop 3
RUN find ${FLUME_HOME}/lib -name "guava-*.jar"            -delete 2>/dev/null; \
    find ${FLUME_HOME}/lib -name "hadoop-*.jar"           -delete 2>/dev/null; \
    find ${FLUME_HOME}/lib -name "htrace-core*.jar"       -delete 2>/dev/null; \
    find ${FLUME_HOME}/lib -name "slf4j-log4j12-*.jar"    -delete 2>/dev/null; true

COPY flume.conf   ${FLUME_HOME}/conf/flume.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
