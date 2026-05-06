FROM apache/hadoop:3
USER root
# flume-ng uses `which hadoop` to locate Hadoop jars; apache/hadoop:3 lacks `which`
# and CentOS 7 mirrors are offline, so provide a POSIX shim.
RUN printf '#!/bin/sh\ncommand -v "$1"\n' > /usr/local/bin/which \
    && chmod +x /usr/local/bin/which
RUN curl -fsSL -o /tmp/flume.tar.gz https://downloads.apache.org/flume/1.11.0/apache-flume-1.11.0-bin.tar.gz \
    && tar -xzf /tmp/flume.tar.gz -C /opt/ \
    && mv /opt/apache-flume-1.11.0-bin /opt/flume \
    && rm /tmp/flume.tar.gz
ENV FLUME_HOME=/opt/flume
ENV HADOOP_HOME=/opt/hadoop
ENV PATH=$PATH:$HADOOP_HOME/bin:$FLUME_HOME/bin
COPY flume.conf /opt/flume/conf/flume.conf
EXPOSE 44444
CMD ["flume-ng", "agent", "--conf", "/opt/flume/conf", "--conf-file", "/opt/flume/conf/flume.conf", "--name", "agent1", "-Dflume.root.logger=INFO,console"]
