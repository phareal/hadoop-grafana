#!/bin/bash
echo "=== FIX NameNode — Groupe 6 ==="
echo "1) Fix rapide  2) Reset complet"
read -p "Choix : " c
docker-compose down
if [ "$c" = "1" ]; then
  mkdir -p ./data/nameNode ./data/dataNode && chmod -R 777 ./data
  docker-compose up -d && sleep 20
  docker exec -it namenode bash -c "hdfs namenode -format -force"
  docker-compose restart
else
  docker-compose down -v && rm -rf ./data
  mkdir -p ./data/nameNode ./data/dataNode && chmod -R 777 ./data
  docker-compose up -d && sleep 30
  docker exec -it namenode bash -c "hdfs namenode -format -force"
  docker-compose restart
fi
docker-compose ps
