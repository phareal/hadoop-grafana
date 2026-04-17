# Hadoop Big Data — Groupe 6

Cluster Hadoop complet optimisé pour consommer moins de 3GB de RAM.

## Équipe — Groupe 6 — Big Data — Lomé Business School
- LAWSON-DJITO Latévi Steven Antoine
- POTCHONA Essosolam Justin
- AMEDON Roland

## Architecture
- **HDFS** : NameNode + DataNode
- **YARN** : ResourceManager + NodeManager
- **Flume** : Collecte de logs → HDFS
- **Log Generator** : Simulation étudiants / cours
- **Dashboard Flask** : Visualisation temps réel
- **Grafana** : Monitoring avancé
- **Caddy** : Reverse proxy nip.io

## Démarrage rapide

```bash
chmod +x scripts/*.sh healthcheck.sh
docker-compose up -d --build
sleep 35
docker exec -it namenode bash -c "hdfs namenode -format -force"
docker-compose restart namenode
./healthcheck.sh
```

## URLs
- http://groupe6.127.0.0.1.nip.io — Accueil
- http://namenode.127.0.0.1.nip.io — NameNode HDFS
- http://yarn.127.0.0.1.nip.io — YARN
- http://flume.127.0.0.1.nip.io — Dashboard Flume
- http://grafana.127.0.0.1.nip.io — Grafana

## Consommation RAM cible : ~2.2 GB total
