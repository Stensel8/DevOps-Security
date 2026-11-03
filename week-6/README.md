# Week 6: Monitoring, traceability en pentesten

In deze week staat het zicht op de omgeving centraal. Een cluster kan goed beveiligd zijn op het moment dat het wordt opgezet, maar daarna verandert er van alles: er komen nieuwe versies, nieuwe kwetsbaarheden en soms ook aanvallers. Om dat op te merken zijn drie dingen nodig. Monitoring laat zien of alles op dit moment goed draait. Traceability laat zien wat er precies in een workload zit, ook achteraf. Pentesten laat zien hoe het systeem zich gedraagt als iemand het actief aanvalt.

Deze week bestaat uit drie opdrachten. Paragraaf 6.1 beschrijft de installatie van Prometheus en twee alerts die relevant zijn voor security. Paragraaf 6.2 gaat over traceability met de Trivy Operator, en paragraaf 6.3 bevat een advies aan SolidApps over geautomatiseerd pentesten.

## 6.1 Prometheus en twee security-relevante alerts

Voor deze opdracht heb ik Prometheus geïnstalleerd. Prometheus is een open-source systeem voor monitoring en alerting. Het haalt op vaste momenten meetgegevens op bij de onderdelen van een systeem, slaat die op als tijdreeksen, en kan op basis van regels een alert versturen [(Prometheus Authors, z.d.-b)](https://prometheus.io/docs/introduction/overview/).

Ik heb de Helm-chart `kube-prometheus-stack` gebruikt. Die installeert in één keer Prometheus, Alertmanager, Grafana, kube-state-metrics en node-exporter [(Prometheus Community, z.d.)](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack). Omdat de nodes maar 4 GB geheugen hebben, heb ik de geheugenlimieten verlaagd en de gegevens maar één dag laten bewaren:

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.retention=1d
```

node-exporter verzamelt de gegevens van de nodes zelf, zoals CPU en geheugen, en draait op beide nodes. Naast de alerts die de chart standaard meelevert, heb ik in [kubernetes/prometheus-alerts.yaml](../kubernetes/prometheus-alerts.yaml) twee eigen alertregels gemaakt [(Prometheus Authors, z.d.-a)](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/):

- **`QuoterXPHerhaaldeRestarts`:** gaat af als de pod van de app binnen 15 minuten opnieuw is gestart. Dat kan een gewone crash zijn, maar het is ook wat je ziet als iemand een kwetsbaarheid in de app misbruikt waardoor die onderuitgaat.
- **`NodeHoogCPUGebruik`:** gaat af als een node langer dan 2 minuten boven de 80% CPU zit. Dat is op zich onschuldig, maar zo valt ook een proces op dat er niet hoort.

Om de eerste alert echt te laten afgaan, heb ik het hoofdproces in de container van de app gestopt. Ik heb de pod bewust niet verwijderd, want dan maakt de Deployment een nieuwe pod met een teller op 0. Een paar minuten later stond de alert in Prometheus op `firing`:

```json
{
  "labels": { "alertname": "QuoterXPHerhaaldeRestarts", "severity": "warning" },
  "state": "firing",
  "activeAt": "2026-11-01T17:53:19.163Z"
}
```

## 6.2 Traceability met Trivy

Monitoring laat zien of iets op dit moment goed draait: is de pod bereikbaar, en hoeveel CPU gebruikt een node. Traceability gaat over iets anders: kan worden teruggevonden wat er in een workload zit, en waarom het daar staat, ook achteraf. Op een traditionele server raak je dat overzicht kwijt zodra iemand inlogt en iets installeert. In Kubernetes draait alles vanaf een image met een vaste digest. Daardoor is op elk moment vast te stellen wat er in een pod zit, zonder op de node zelf te kijken.

Voor deze opdracht heb ik de Trivy Operator geïnstalleerd. De Trivy Operator draait in het cluster en scant de workloads daar doorlopend, in plaats van één keer in de pipeline [(Aqua Security, z.d.-b)](https://aquasecurity.github.io/trivy-operator/latest/). Dat geldt voor alle workloads, dus ook voor die van Prometheus en van K3s zelf.

Voor elke workload maakt de operator een `VulnerabilityReport`. Het eigen image heeft 0 kwetsbaarheden, net als bij Docker Scout in week 3. Daarnaast maakt de operator een `ConfigAuditReport`. Dat is geen scan van het image, maar een controle van de Kubernetes-objecten zelf, zoals de Deployment en de Service [(Aqua Security, z.d.-a)](https://aquasecurity.github.io/trivy-operator/latest/docs/crds/configaudit-report/). Bij de Deployment van de app vond hij twee punten:

```
AVD-KSV-0110: Workloads in the default namespace (LOW)
AVD-KSV-0125: Restrict container images to trusted registries (MEDIUM)
```

Het eerste punt is dat de app in de namespace `default` draait in plaats van in een eigen namespace. Dat staat ook in de CIS Kubernetes Benchmark, bij aanbeveling 5.7.4. Twee verschillende tools komen hier dus los van elkaar tot dezelfde conclusie. Het tweede punt gaat over het beperken van images tot vertrouwde registries. Dat is in deze opstelling niet ingesteld, en zou ik in productie wel doen.

## 6.3 Geautomatiseerd pentesten bij SolidApps

Scanners zoals Snyk, CodeQL, Trivy en Docker Scout uit week 2 en 3 vinden bekende kwetsbaarheden in code en images. Ze testen niet hoe het systeem zich gedraagt als iemand het actief aanvalt. Dat gat vult geautomatiseerd pentesten. In deze paragraaf geef ik SolidApps advies over drie soorten tools.

- **DAST tegen de draaiende app:** ZAP test een webapplicatie van buitenaf, zoals een aanvaller dat ook zou doen. De baseline scan van ZAP voert geen echte aanvallen uit, maar kijkt passief naar wat de applicatie teruggeeft, en is daardoor geschikt voor een pipeline [(ZAP, z.d.)](https://www.zaproxy.org/docs/docker/baseline-scan/). Ik zou die na Deploy laten lopen, tegen de net uitgerolde testomgeving.
- **Het cluster zelf testen:** hiervoor werd vaak kube-hunter gebruikt, maar die tool wordt niet meer onderhouden. Aqua Security raadt nu Trivy aan voor het scannen van Kubernetes-clusters [(Aqua Security, z.d.-c)](https://github.com/aquasecurity/kube-hunter). Een alternatief is Kubescape, dat een draaiend cluster toetst aan frameworks met controles en ook kwetsbaarheden in het cluster in kaart brengt [(Kubescape Authors, z.d.)](https://kubescape.io/docs/). Zo'n scan zou ik gepland laten draaien, bijvoorbeeld wekelijks, net als de scan in [trivy.yml](../.github/workflows/trivy.yml) die elke maandagochtend draait.
- **Snelle controles met templates:** Nuclei is een scanner die werkt met templates van de community, voor bekende kwetsbaarheden en fouten in de configuratie [(ProjectDiscovery, z.d.)](https://github.com/projectdiscovery/nuclei). Die kan bij elke uitrol naar een testomgeving draaien.

Daarbij gelden twee voorwaarden. Ten eerste test SolidApps altijd tegen een test- of stagingomgeving, en nooit tegen productie zonder toestemming en een afgesproken moment. Ten tweede komen de resultaten op dezelfde plek als die van CodeQL en Trivy, zoals het Security-tabblad van GitHub, zodat het team niet op drie plekken hoeft te kijken.

Geautomatiseerde tools vinden bekende patronen, maar fouten in de logica van een applicatie vinden ze meestal niet. Mijn advies is daarom om daarnaast regelmatig een pentest door een mens te laten uitvoeren.

## Bronnen

Aqua Security. (z.d.-a). *ConfigAuditReport*. Trivy Operator. https://aquasecurity.github.io/trivy-operator/latest/docs/crds/configaudit-report/

Aqua Security. (z.d.-b). *Home*. Trivy Operator. https://aquasecurity.github.io/trivy-operator/latest/

Aqua Security. (z.d.-c). *kube-hunter* \[Broncode\]. GitHub. https://github.com/aquasecurity/kube-hunter

Kubescape Authors. (z.d.). *Documentation overview*. Kubescape. https://kubescape.io/docs/

ProjectDiscovery. (z.d.). *Nuclei* \[Broncode\]. GitHub. https://github.com/projectdiscovery/nuclei

Prometheus Authors. (z.d.-a). *Alerting rules*. Prometheus. https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/

Prometheus Authors. (z.d.-b). *Overview*. Prometheus. https://prometheus.io/docs/introduction/overview/

Prometheus Community. (z.d.). *kube-prometheus-stack* \[Broncode\]. GitHub. https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack

ZAP. (z.d.). *ZAP: Baseline scan*. https://www.zaproxy.org/docs/docker/baseline-scan/
