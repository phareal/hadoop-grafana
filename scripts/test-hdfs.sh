#!/bin/bash
docker exec -it namenode bash -c "
  hdfs dfs -mkdir -p /user/hadoop/test
  echo 'Hello Groupe 6' > /tmp/test.txt
  hdfs dfs -put -f /tmp/test.txt /user/hadoop/test/
  hdfs dfs -ls /user/hadoop/test/
  hdfs dfsadmin -report
"
