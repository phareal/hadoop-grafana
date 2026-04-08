# Hadoop + Flume + Grafana — Monitoring Big Data en temps réel

Cluster Hadoop Docker complet avec pipeline d'ingestion Apache Flume et dashboard Grafana live.

---

## Architecture

```
log-generator ──► spool/ ──► Flume ──► HDFS (namenode)
     │                                     │
     └──► MySQL (events) ◄── Flask ◄────────┘
                               │
                           Grafana (Infinity + MySQL datasources)
```

---

## Services et interfaces web

| Service         | URL                     | Login             | Rôle                            |
|----------------|-------------------------|-------------------|---------------------------------|
| **Grafana**     | http://localhost:3000   | admin / hadoop2026 | Dashboard monitoring complet    |
| Flask Dashboard | http://localhost:5000   | —                 | API REST JSON pour Grafana       |
| NameNode HDFS   | http://localhost:9870   | —                 | Fichiers Flume dans HDFS        |
| ResourceManager | http://localhost:8088   | —                 | Jobs YARN en cours              |
| Adminer MySQL   | http://localhost:8080   | root / root       | Base de données universite      |
| HistoryServer   | http://localhost:19888  | —                 | Historique MapReduce            |

---

## Structure du projet

```
hadoop/
├── docker-compose.yml
├── config/                        # Config Hadoop (core, hdfs, yarn, mapred)
├── data/                          # Volumes persistants NameNode/DataNode
├── mysql/
│   └── init.sql                   # Schéma + données d'exemple
├── log-generator/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── generate_logs.py           # Génère des logs aléatoires → spool + MySQL
├── flume/
│   ├── Dockerfile                 # Base apache/hadoop:3 + Flume 1.11.0
│   ├── flume.conf                 # Agent spooldir → HDFS
│   └── entrypoint.sh
├── dashboard/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app.py                     # Flask : 4 endpoints REST pour Grafana
└── grafana/
    ├── Dockerfile                 # grafana/grafana + plugin Infinity pré-installé
    ├── provisioning/
    │   ├── datasources/
    │   │   ├── mysql.yml          # Datasource MySQL-Hadoop (uid: mysql-hadoop)
    │   │   └── infinity.yml       # Datasource Flume-API   (uid: flume-api)
    │   └── dashboards/
    │       └── dashboards.yml     # Chargement auto du dashboard
    └── dashboards/
        └── flume.json             # Dashboard 10 panels — chargé au démarrage
```

---

## Démarrage

### Première fois (avec internet — build des images)

```bash
# macOS/Linux
docker-compose up -d --build

# Windows PowerShell
docker compose up -d --build
```

> Le build télécharge Flume 1.11.0 et le plugin Grafana Infinity.  
> Après ce premier build, **tout fonctionne hors-ligne**.

### Vérifications

```bash
# Statut de tous les services
docker-compose ps

# Logs Grafana (attendre "HTTP Server Listen" avant d'ouvrir le navigateur)
docker logs -f grafana

# Logs Flask
docker logs -f dashboard

# Logs Flume
docker logs -f flume

# Logs du générateur de logs
docker logs -f log-generator
```

### Vérifier les datasources Grafana via API

```bash
curl -s http://admin:hadoop2026@localhost:3000/api/datasources | python3 -m json.tool

# Vérifier les dashboards chargés
curl -s http://admin:hadoop2026@localhost:3000/api/search | python3 -m json.tool
```

### Vérifier les métriques Flask

```bash
curl http://localhost:5000/api/metrics
curl http://localhost:5000/api/throughput
curl http://localhost:5000/api/log-distribution
curl http://localhost:5000/api/logs
```

### Vérifier les fichiers dans HDFS

```bash
docker exec namenode hdfs dfs -ls /flume/logs/
docker exec namenode hdfs dfs -du -h /flume/logs/
```

---

## Arrêt et nettoyage

```bash
# Arrêter sans supprimer les volumes (données conservées)
docker-compose down

# Arrêter ET supprimer les volumes (reset complet)
docker-compose down -v
```

---

## Endpoints API Flask (dashboard:5000)

| Endpoint                  | Format retourné                              | Utilisé par          |
|--------------------------|----------------------------------------------|----------------------|
| `GET /api/metrics`        | `[{total_events, info_count, warn_count, error_count, events_per_sec, hdfs_files, hdfs_size_mb}]` | Panels stat + gauge  |
| `GET /api/throughput`     | `[{time: unix_ms, value: float}]`            | Panel Time Series    |
| `GET /api/log-distribution` | `[{INFO: int, WARN: int, ERROR: int}]`     | Panel Pie Chart      |
| `GET /api/logs`           | `[{time, level, message}]`                   | Panel Table Logs     |

---

## Dashboard Grafana — 10 panels

| # | Type        | Titre                          | Source      |
|---|-------------|-------------------------------|-------------|
| 1 | Stat        | Total Events Ingested          | Flume API   |
| 2 | Stat        | Events / sec                   | Flume API   |
| 3 | Stat        | ERROR Count (rouge > 50)       | Flume API   |
| 4 | Time Series | Débit Flume en temps réel      | Flume API   |
| 5 | Pie Chart   | Distribution INFO/WARN/ERROR   | Flume API   |
| 6 | Bar Chart   | Étudiants par filière          | MySQL       |
| 7 | Table       | Dernières inscriptions         | MySQL       |
| 8 | Gauge       | HDFS Storage Used              | Flume API   |
| 9 | Table       | Log Stream Flume               | Flume API   |
|10 | Stat        | Fichiers HDFS créés            | Flume API   |

- Rafraîchissement : **1 seconde**
- Fenêtre temporelle : **15 dernières minutes**
- Thème : **Dark**

---

## Alerte Grafana (bonus exposé)

Le panel **ERROR Count** change de couleur automatiquement :
- Vert → moins de 10 erreurs
- Orange → entre 10 et 50 erreurs
- **Rouge vif** → plus de 50 erreurs (effet waouh garanti)

Pour créer une notification d'alerte via l'API Grafana :

```bash
# 1. Créer un contact point (notification console)
curl -s -X POST http://admin:hadoop2026@localhost:3000/api/v1/provisioning/contact-points \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Flume-Alert",
    "type": "email",
    "settings": {"addresses": "equipe@universite.fr"}
  }'

# 2. La règle d'alerte se configure dans Grafana UI :
#    Alerting → Alert rules → New alert rule
#    Condition : query(A, 10s, now) IS ABOVE 50
#    Labels : severity=critical
```

---

## Scénario démo exposé (5 min)

| Temps | Action                                         | Ce que le public voit                        |
|-------|------------------------------------------------|----------------------------------------------|
| 0:00  | Ouvrir http://localhost:3000                   | Dashboard sombre, tous les panels actifs     |
| 0:30  | Montrer le Time Series                         | Ligne orange qui monte en temps réel         |
| 1:30  | Pointer ERROR Count                            | Compteur rouge avec seuil visible            |
| 2:00  | Montrer le Pie Chart                           | Camembert INFO/WARN/ERROR animé              |
| 2:30  | Panel MySQL — Étudiants par filière            | Bar chart coloré avec les données réelles    |
| 3:00  | Panel MySQL — Dernières inscriptions           | Table avec notes colorées (vert/orange/rouge)|
| 3:30  | Panel HDFS Gauge                               | Jauge qui augmente au fil des ingestions     |
| 4:00  | Panel Log Stream                               | Logs Flume colorés qui défilent              |
| 4:30  | Changer le Time Range → "Last 5m"              | Vue resserrée sur le pic d'activité          |
| 5:00  | Conclusion                                     | "C'est ce qu'on fait en prod chez Netflix"   |

---

## Dépannage

**Grafana ne charge pas les datasources**
```bash
docker logs grafana | grep -i "provisioning\|error\|plugin"
# Vérifier que le plugin Infinity est installé :
docker exec grafana grafana-cli plugins ls | grep infinity
```

**Flume ne démarre pas**
```bash
docker logs flume
# Vérifier que le NameNode est healthy :
docker-compose ps namenode
```

**Pas de données dans les panels Infinity**
```bash
# Tester l'API directement depuis le conteneur Grafana :
docker exec grafana wget -qO- http://dashboard:5000/api/metrics
```

**MySQL ne répond pas**
```bash
docker exec mysql mysqladmin ping -uroot -proot
```

---

## Équipe

Projet universitaire — Big Data & Architecture distribuée  
Cluster Hadoop 3 · Apache Flume 1.11.0 · MySQL 8.0 · Grafana 10 · Flask 3
