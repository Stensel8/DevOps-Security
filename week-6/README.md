# Week 6

## 6.1 Prometheus en twee security-relevante alerts

Prometheus geïnstalleerd met de `kube-prometheus-stack` Helm-chart (Prometheus, Alertmanager, Grafana, kube-state-metrics en node-exporter in één), met wat lagere resource-limieten omdat de nodes maar 4 GB RAM hebben:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.retention=1d \
  --set prometheus.prometheusSpec.resources.requests.memory=256Mi \
  --set prometheus.prometheusSpec.resources.limits.memory=512Mi \
  --set grafana.resources.requests.memory=128Mi \
  --set grafana.resources.limits.memory=256Mi
```

node-exporter draait als DaemonSet, dus op beide nodes:

```
$ kubectl get pods -n monitoring -o wide | grep node-exporter
kube-prometheus-stack-prometheus-node-exporter-wtgn8   1/1   Running   0   cn2
kube-prometheus-stack-prometheus-node-exporter-z68h8   1/1   Running   0   cn1
```

Twee eigen, security-relevante alerts gezet in [kubernetes/prometheus-alerts.yaml](../kubernetes/prometheus-alerts.yaml), naast de alerts die de chart al standaard meelevert. `QuoterXPHerhaaldeRestarts` gaat af als de app-pod binnen 15 minuten herstart: kan een gewone crash zijn, maar is ook precies wat je zou zien als iemand een kwetsbaarheid in de app raakt waardoor hij onderuitgaat. En `NodeHoogCPUGebruik` gaat af als een node langer dan 2 minuten boven de 80% CPU zit. Op zich onschuldig, maar wel het soort signaal waarmee je een proces opmerkt dat daar niet hoort te draaien.

```bash
kubectl apply -f kubernetes/prometheus-alerts.yaml
```

Om de eerste alert echt te laten afgaan heb ik de app-container laten crashen (niet de pod verwijderd, want dan maakt de Deployment gewoon een nieuwe pod met restart-teller op 0; dit raakt de teller van de bestaande pod):

```
$ kubectl exec deploy/devops-security -- kill 1
$ kubectl get pods -l app=quoterxp
NAME                               READY   STATUS    RESTARTS      AGE
devops-security-6fdcbf5c57-xnfqn   1/1     Running   1 (7s ago)    23s
```

Een paar minuten later (de regel heeft `for: 1m`, plus de scrape-interval) staat de alert op `firing` in de Prometheus-API:

```json
{
  "labels": { "alertname": "QuoterXPHerhaaldeRestarts", "pod": "devops-security-6fdcbf5c57-xnfqn", "severity": "warning" },
  "annotations": {
    "description": "Onverwachte restart van de app-pod. Even de pod-logs checken waarom.",
    "summary": "devops-security pod is herstart"
  },
  "state": "firing",
  "activeAt": "2026-11-01T17:53:19.163Z"
}
```

## 6.2 Traceability met Trivy

Monitoring (6.1) vertelt je of iets nu goed draait: is de pod up, hoeveel CPU gebruikt een node. Traceability vertelt je iets anders: kun je terugvinden wát er in een workload zit en waarom dat daar hoort te staan, ook achteraf. Bij een traditionele server installeer je een package en ben je het overzicht kwijt zodra iemand anders inlogt en iets toevoegt. In Kubernetes draait alles van een image met een vaste digest, dus je kunt op elk moment opnieuw vaststellen wat er precies in een pod zit, zonder op de node zelf te hoeven kijken.

De Trivy-operator doet dat continu voor het hele cluster, niet alleen voor ons eigen image:

```bash
helm repo add aqua https://aquasecurity.github.io/helm-charts
helm install trivy-operator aqua/trivy-operator -n trivy-system --create-namespace \
  --set trivy.resources.requests.memory=100Mi --set trivy.resources.limits.memory=300Mi
```

Voor elke workload in elke namespace komt er een `VulnerabilityReport`:

```
$ kubectl get vulnerabilityreports -A
NAMESPACE     NAME                                          REPOSITORY                     TAG
default       replicaset-devops-security-...-quoterxp       stensel8/devops-security       ce54d349...
kube-system   daemonset-svclb-traefik-...                    rancher/klipper-lb             v0.4.17
monitoring    statefulset-...                                prometheus/prometheus          v3.15.1-distroless
...

$ kubectl get vulnerabilityreport -n default replicaset-devops-security-d5cd6948-quoterxp -o jsonpath='{.report.summary}'
{"criticalCount":0,"highCount":0,"lowCount":0,"mediumCount":0,"noneCount":0,"unknownCount":0}
```

Ons eigen image staat op 0, wat overeenkomt met Docker Scout in week 3. Trivy-operator maakt daarnaast ook `ConfigAuditReport`'s: geen imagescans, maar checks op de Kubernetes-objecten zelf (Deployment, Service, Ingress, NetworkPolicy). Die vond twee echte dingen bij onze eigen Deployment:

```
$ kubectl get configauditreport -n default replicaset-devops-security-d5cd6948 -o jsonpath='{range .report.checks[?(@.success==false)]}{.checkID}: {.title} ({.severity}){"\n"}{end}'
AVD-KSV-0110: Workloads in the default namespace (LOW)
AVD-KSV-0125: Restrict container images to trusted registries (MEDIUM)
```

De eerste is precies wat ik in week 5 (CIS 5.7.4) ook al tegenkwam: de app draait in `default` in plaats van een eigen namespace. Mooi dat twee verschillende tools (kube-bench en Trivy-operator) onafhankelijk van elkaar dezelfde conclusie trekken. De tweede komt doordat Trivy-operator standaard alleen een kleine lijst "vertrouwde" registries kent en Docker Hub daar niet automatisch in zit; dat is geen fout in mijn setup, maar een instelling die ik bewust zou aanpassen (`trivyOperator.trivy.trustedRegistries`) als ik dit echt in productie zou gebruiken.

## 6.3 Geautomatiseerd pentesten bij SolidApps

Scanners zoals Snyk, CodeQL, Trivy en Docker Scout (week 2 en 3) vinden bekende kwetsbaarheden in code en images, maar testen niet actief hoe het systeem zich gedraagt onder aanval. Dat is het gat dat geautomatiseerd pentesten opvult.

Tegen de draaiende app zou ik OWASP ZAP inzetten, in baseline- of full-scan-modus, in de pipeline na Deploy, tegen de net uitgerolde omgeving (zelfde gedachte als mijn advies in 3.7). Die vindt dingen zoals ontbrekende headers, kwetsbare endpoints en verkeerde cookie-instellingen, van buitenaf, zoals een aanvaller het ook zou zien. Op clusterniveau test kube-hunter actief tegen een live Kubernetes-cluster (API-server, kubelet, open poorten), in plaats van statisch de manifests te lezen zoals kube-bench en Trivy config doen. Dat is een actieve aanval, dus die zou ik gepland laten draaien, bijvoorbeeld wekelijks zoals de Trivy-cron in [trivy.yml](../.github/workflows/trivy.yml), en alleen tegen een testcluster, nooit ongepland tegen productie. Voor webapplicatie-fuzzing is Nuclei handig, met community-templates voor bekende CVE's en misconfiguraties, snel genoeg om op elke deploy naar een testomgeving te draaien.

Voorwaarde voor dit alles: altijd tegen een test- of staging-omgeving, nooit tegen productie zonder change window en toestemming vooraf, en de scanresultaten in hetzelfde Security-tabblad als CodeQL en Trivy, zodat het team niet drie verschillende plekken hoeft na te kijken.

Tooling-advies: OWASP ZAP voor DAST in de pipeline, kube-hunter periodiek tegen een testcluster, Nuclei voor snelle, template-gebaseerde checks op elke deploy. Voor een jaarlijkse, diepere controle blijft een externe, menselijke pentest nodig: geautomatiseerde tools vinden bekende patronen, geen logica- of ketenfouten die een mens wel ziet.

**Bronnen**

- OWASP Foundation. (z.d.). *OWASP ZAP*. [https://www.zaproxy.org/](https://www.zaproxy.org/)
- OWASP Foundation. (z.d.). *ZAP Baseline Scan (Docker)*. [https://www.zaproxy.org/docs/docker/baseline-scan/](https://www.zaproxy.org/docs/docker/baseline-scan/)
- Aqua Security. (z.d.). *kube-hunter*. GitHub. [https://github.com/aquasecurity/kube-hunter](https://github.com/aquasecurity/kube-hunter)
- ProjectDiscovery. (z.d.). *Nuclei*. GitHub. [https://github.com/projectdiscovery/nuclei](https://github.com/projectdiscovery/nuclei)
