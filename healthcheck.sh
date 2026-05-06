#!/bin/bash
G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; NC='\033[0m'; B='\033[1m'
OK=0; FAIL=0

http() {
  local label="$1"; local url="$2"
  S=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 -H "Host: $(echo "$url" | sed -E 's|^https?://||;s|/.*||')" "$url")
  if [[ "$S" =~ ^(200|301|302)$ ]]; then
    echo -e "  ${G}✓${NC} $label [${S}]"; OK=$((OK+1))
  else
    echo -e "  ${R}✗${NC} $label [${S}] → $url"; FAIL=$((FAIL+1))
  fi
}

container() {
  local label="$1"; local name="$2"
  S=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null)
  if [ "$S" = "running" ]; then
    echo -e "  ${G}✓${NC} $label"; OK=$((OK+1))
  else
    echo -e "  ${R}✗${NC} $label [${S:-not found}]"; FAIL=$((FAIL+1))
  fi
}

ram() {
  echo ""
  echo -e "${B}RAM par conteneur :${NC}"
  docker stats --no-stream --format "  {{.Name}}: {{.MemUsage}}" \
    namenode datanode resourcemanager nodemanager \
    flume flume-dashboard crud-app grafana groupe6-caddy 2>/dev/null
}

echo -e "\n${B}=====================================${NC}"
echo -e "${B}  Groupe 6 — Healthcheck Cluster${NC}"
echo -e "${B}=====================================${NC}\n"

echo -e "${B}[1/4] Conteneurs${NC}"
container "NameNode"        "namenode"
container "DataNode"        "datanode"
container "ResourceManager" "resourcemanager"
container "NodeManager"     "nodemanager"
container "Flume"           "flume"
container "Dashboard"       "flume-dashboard"
container "CRUD App"        "crud-app"
container "Grafana"         "grafana"
container "Caddy"           "groupe6-caddy"

echo -e "\n${B}[2/4] Ports localhost${NC}"
http "NameNode    :9870" "http://localhost:9870"
http "YARN        :8088" "http://localhost:8088"
http "Dashboard   :5000" "http://localhost:5000"
http "Grafana     :3000" "http://localhost:3000"

echo -e "\n${B}[3/4] Domaines nip.io${NC}"
http "groupe6.127.0.0.1.nip.io"  "http://groupe6.127.0.0.1.nip.io"
http "namenode.127.0.0.1.nip.io" "http://namenode.127.0.0.1.nip.io"
http "yarn.127.0.0.1.nip.io"     "http://yarn.127.0.0.1.nip.io"
http "flume.127.0.0.1.nip.io"    "http://flume.127.0.0.1.nip.io"
http "grafana.127.0.0.1.nip.io"  "http://grafana.127.0.0.1.nip.io"

echo -e "\n${B}[4/4] HDFS${NC}"
if docker exec namenode bash -c "hdfs dfsadmin -report" &>/dev/null; then
  echo -e "  ${G}✓${NC} NameNode accessible"; OK=$((OK+1))
else
  echo -e "  ${R}✗${NC} NameNode inaccessible"; FAIL=$((FAIL+1))
fi

ram

echo -e "\n${B}=====================================${NC}"
TOTAL=$((OK+FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${G}${B}TOUT OK — $OK/$TOTAL tests passés${NC}"
  echo -e "  ${G}Cluster Groupe 6 prêt pour l'exposé !${NC}"
else
  echo -e "  ${Y}${B}$OK/$TOTAL passés — $FAIL échec(s)${NC}"
fi
echo -e "${B}=====================================${NC}\n"
