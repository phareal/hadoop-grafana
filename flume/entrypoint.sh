#!/bin/bash
set -e

echo "[flume] Waiting for HDFS NameNode to be ready..."
until curl -sf http://namenode:9870 > /dev/null 2>&1; do
    echo "[flume]   NameNode not ready, retrying in 5s..."
    sleep 5
done
echo "[flume] NameNode is up."

echo "[flume] Creating HDFS directory /flume/logs/..."
hdfs dfs -mkdir -p /flume/logs/"$(date +%Y%m%d)" 2>/dev/null || true
echo "[flume] HDFS directory ready."

# Ajouter les JARs Hadoop au classpath de Flume (HDFS sink en a besoin)
export FLUME_CLASSPATH="\
${HADOOP_HOME}/share/hadoop/common/*:\
${HADOOP_HOME}/share/hadoop/common/lib/*:\
${HADOOP_HOME}/share/hadoop/hdfs/*:\
${HADOOP_HOME}/share/hadoop/hdfs/lib/*:\
${HADOOP_HOME}/share/hadoop/mapreduce/*:\
${HADOOP_HOME}/share/hadoop/tools/lib/*"

export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop

echo "[flume] Starting Flume agent..."
exec flume-ng agent \
    --conf     "${FLUME_HOME}/conf" \
    --conf-file "${FLUME_HOME}/conf/flume.conf" \
    --name     agent \
    -Dflume.root.logger=INFO,console \
    -Dorg.apache.flume.log.rawdata=false
