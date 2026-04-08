# Image Grafana avec le plugin Infinity pré-installé.
# Bake une seule fois avec internet → fonctionne ensuite hors-ligne.
FROM grafana/grafana:latest
USER root
RUN grafana-cli plugins install yesoreyeram-infinity-datasource
USER grafana
