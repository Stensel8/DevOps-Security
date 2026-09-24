# Week 1

Voor week 1 is het de bedoeling dat ik de testomgeving neerzet: twee VM's met Kubernetes, een pipeline in GitHub Actions en Docker Hub voor de images. Als ik iets in de code aanpas, moet dat vanzelf op het cluster komen te draaien. Daarnaast schrijf ik twee adviezen voor SolidApps, over standaarden (1.2) en over CVE's (1.3).

## 1.1 Bootomgeving

Eerst heb ik op Docker Hub een repository en een access token gemaakt. Die staan als secrets in GitHub, zodat de pipeline er images naartoe kan pushen. Normaal staat de repository op Private. Voor de docent zet ik hem soms tijdelijk op Public, zodat die de layers en vulnerabilities kan zien.

![Docker Hub token](images/dockerhub-pat.png)
![GitHub secrets](images/github-secrets.png)

Daarna heb ik in het AWS Learner Lab twee VM's gemaakt met Ubuntu Server 26.04 LTS, type `t2.medium` en 15 GiB opslag (de standaard 8 GiB is te weinig). Ze gebruiken dezelfde key pair en heten CN1 en CN2.

![AMI en instance type](images/ec2-ami-instance-type.png)
![Key pair](images/ec2-keypair.png)
![Opslag en aantal](images/ec2-storage-2-instances.png)

IPv6 staat standaard uit. Dat heb ik als extra aangezet, dus beide VM's hebben nu een IPv4- en een IPv6-adres.

![CN1 en CN2 draaien](images/ec2-instances.png)

Vervolgens verbind ik met SSH via het DNS-adres. Dat werkt het best, omdat sommige machines zowel IPv4 als IPv6 hebben. Ik update de machine en zet de hostname goed, zodat die overeenkomt met de naam in AWS.

```bash
chmod 400 "DevOps-Security-stensel8.pem"
ssh -i "DevOps-Security-stensel8.pem" ubuntu@<public-dns>
sudo apt update && sudo apt upgrade -y
sudo hostnamectl hostname CN1      # CN2 op de andere node
sudo reboot
```

![apt update](images/ssh-apt-update.png)
![Hostname en reboot](images/hostname-reboot.png)

Dan installeer ik K3s met mijn eigen script [install-k3s.sh](../kubernetes/install-k3s.sh): `--control-plane` op CN1 en `--worker` op CN2. Het script draai ik met `sudo`, maar daarna beheer ik het cluster als gewone gebruiker. Het script zet de kubeconfig namelijk op `0640` voor mijn groep, dus `kubectl` werkt zonder `sudo`. Bij de installatie uit de handleiding is die alleen voor root leesbaar, en moet je steeds `sudo kubectl` gebruiken.

```bash
sudo ./install-k3s.sh --control-plane                                              # CN1
sudo ./install-k3s.sh --worker --url https://<private-ip-cn1>:6443 --token <token> # CN2
kubectl get nodes                                                                  # CN1
```

![Beide nodes Ready](images/k3s-nodes-ready.png)

Daarna heb ik op CN1 een self-hosted GitHub runner geïnstalleerd (GitHub, Settings, Actions, Runners, New self-hosted runner) en CN1 als runner gejoind. Zie de screenshots.

![Nog geen runners](images/runner-nieuw.png)
![Runner installeren en starten](images/runner-config.png)

De runner ging meteen aan de slag met de Deploy-stap die stond te wachten. Omdat de Docker Hub-repository toen nog public was, kon het cluster het image zonder inloggen ophalen, dus de deploy lukte meteen.

Voor het pull-secret van het cluster heb ik een tweede token gemaakt in Docker Hub, met alleen lees-rechten. CN1 hoeft namelijk niks naar mijn repository te schrijven. Dit token staat ook als secret in GitHub (`DOCKER_HUB_PULL_PAT`), zodat de runner het kan gebruiken. De deploy-stap maakt er bij elke run het pull-secret `regcred` mee aan. In de handleiding maak je dat secret met een `kubectl create secret`-commando op de master node, en dan staat je wachtwoord in je bash history. Nu staan alle secrets op één plek in GitHub. En als ik de runner vervang of er een bij zet, hoef ik niks over te zetten.

![Docker Hub-token met alleen lezen](images/docker-token-read-only.png)
![GitHub-secret voor het pull-token](images/github-secret-pull-pat.png)

Vervolgens heb ik de repository op Private gezet. Het cluster kan het image nog steeds ophalen. Als ik de pod verwijder, maakt de Deployment een nieuwe pod die het image met `regcred` pullt, en die komt gewoon op `Running`.

![Repository op Private zetten](images/dockerhub-private.png)

```
$ kubectl get secret regcred
NAME      TYPE                             DATA   AGE
regcred   kubernetes.io/dockerconfigjson   1      5m15s
$ kubectl delete pod -l app=quoterxp
pod "student-devsecops-64fd5b7554-8p6hk" deleted from default namespace
$ kubectl get pods
NAME                                 READY   STATUS    RESTARTS   AGE
student-devsecops-64fd5b7554-dzd64   1/1     Running   0          38s
```

Bij de security group heb ik alleen de poorten open gelaten die K3s nodig heeft, volgens de [K3s-documentatie](https://docs.k3s.io/installation/requirements). Tussen de nodes zijn dat TCP 6443 (daar meldt de worker zich aan bij CN1), UDP 8472 (Flannel VXLAN, het netwerk voor de pods) en TCP 10250 (de kubelet). Als bron heb ik daarvoor de security group zelf ingesteld. De poorten 2379-2380, 51820/51821 en 5001 heb ik niet nodig, want ik gebruik geen HA, geen WireGuard en geen Spegel. SSH (22) en de app (NodePort 30000) staan alleen open voor mijn eigen IPv4- en IPv6-adres. HTTP, HTTPS en de regel voor al het verkeer binnen de groep heb ik verwijderd. Mijn IP-adressen heb ik in de screenshot zwart gemaakt.

![Inbound rules van de security group](images/aws-sg-minimale-poorten.png)

Om de app ook via IPv6 te laten werken heb ik in commit [`b67d2b9`](https://github.com/Stensel8/DevOps-Security/commit/b67d2b92c71dee64aab7515fa307ab8d0a59b20d) drie dingen aangepast. Het K3s-script heeft nu een `--dual-stack` optie, de Service heeft `ipFamilyPolicy: PreferDualStack` en de app luistert op `::` in plaats van `0.0.0.0`, dus op IPv4 én IPv6. K3s kan dual-stack alleen aanzetten als je het cluster aanmaakt. Daarom heb ik K3s opnieuw geïnstalleerd met `sudo ./install-k3s.sh --control-plane --dual-stack` en de Deploy opnieuw gedraaid.

![Pipeline na de push](images/pipeline-run.png)

Nu antwoordt de app op poort 30000 via IPv4 en IPv6, op beide nodes:

```bash
curl -4 http://<dns-van-de-node>:30000
curl -6 "http://[<ipv6-van-de-node>]:30000"
```

In de casus heet de Service `ngnix-service` (met een typfout), maar er draait helemaal geen nginx. Het doorsturen van poort 30000 naar poort 5000 in de pod doet kube-proxy, dat in K3s zit. Daarom heb ik het bestand hernoemd naar `kubernetes/service.yaml` en de Service naar `quoterxp-service` (commit [`080731a`](https://github.com/Stensel8/DevOps-Security/commit/080731a)). De nieuwe Service gebruikt dezelfde nodePort 30000, dus de oude moet eerst weg, anders geeft Kubernetes `provided port is already allocated`. Dat doet de deploy-stap nu met `kubectl delete service ngnix-service --ignore-not-found`. Ik heb dat getest op K3s v1.37.0 in Docker: poort 30000 is na het vervangen binnen ongeveer een seconde weer bereikbaar.

```diff
@@ kubernetes/service.yaml:4 @@
-  name: ngnix-service
+  name: quoterxp-service
@@ .github/workflows/build.yaml:167 @@
-          kubectl apply -f kubernetes/nginx-service.yaml
+          kubectl delete service ngnix-service --ignore-not-found
+          kubectl apply -f kubernetes/service.yaml
```

Om te laten zien dat een wijziging in de code vanzelf op het cluster komt, heb ik een paar keer de titel van de app aangepast in `quoter_templates.py` en weer teruggezet ([`de36b32`](https://github.com/Stensel8/DevOps-Security/commit/de36b32), [`ccb61ec`](https://github.com/Stensel8/DevOps-Security/commit/ccb61ec) en [`cb9e32c`](https://github.com/Stensel8/DevOps-Security/commit/cb9e32c)). Na elke commit lopen Validate, Build, Test en Deploy, en de pagina op poort 30000 verandert live. Zie de [screencast](video/live-uitrol.webm) (10 minuten).

### De pipeline

De pipeline staat in [build.yaml](../.github/workflows/build.yaml) en heeft vier jobs. Validate kijkt of `pyproject.toml` en `poetry.lock` kloppen en of de code compileert. Build bouwt het applicatie-image en pusht dat naar Docker Hub, met twee tags: `latest` en de commit-SHA. Het Dockerfile heeft twee stages (zie week 3) en alleen de runtime wordt gepusht (`target: runtime`), dus niet het tussenimage. Test start het image van die commit en wacht tot de app antwoordt. Deploy draait op de runner op CN1. Die maakt het pull-secret aan en past de Deployment toe met de tag van die commit, en de Service. Daarna wacht Deploy tot de uitrol klaar is: de nieuwe pod moet gezond zijn (readiness probe) en de app moet antwoorden via de Service. Lukt dat niet, dan draait Deploy terug naar de vorige versie en wordt de pipeline rood. Op een pull request lopen alleen Validate en Build, zonder push en zonder deploy. De pipeline kan ook handmatig gestart worden via Run workflow, alleen op `main`.

Eerst deed Deploy alleen `kubectl delete deployment --all` en `kubectl apply`. Dat ziet er goed uit, maar de pipeline werd groen zodra Kubernetes de Deployment had aangemaakt, ook als de app niet werkte. Ik heb dat getest in een K3s van dezelfde versie als mijn cluster. Met een image dat wel start maar nooit gezond wordt, eindigde de oude stap met exitcode 0 en stond de pod op `1/1 Running`, terwijl de app niet antwoordde. Ook verwijdert `delete deployment --all` alle Deployments in de namespace en geeft het downtime.

Nu gebruik ik een rolling update en een readiness probe, en de pipeline wacht tot het echt werkt. In dezelfde test gaf een update terwijl ik de app bleef aanroepen 0 mislukte verzoeken bij 29 pogingen. Een kapotte versie en een image dat niet bestaat worden teruggedraaid: de pipeline is dan rood en de oude versie blijft antwoorden. Zie commit [`f3b7bdd`](https://github.com/Stensel8/DevOps-Security/commit/f3b7bdd).

### Onder welk account draait de runner?

De runner draait onder het account `ubuntu` (zie de prompt `ubuntu@CN1` in de screenshot). Dat account kan `sudo` zonder wachtwoord, en de kubeconfig is die van de K3s-admin. De deploy-stap draait dus als iemand met alle rechten op het cluster. Dat is niet veilig voor productie: wie de workflow kan aanpassen, kan met de runner alles doen op CN1 en in het cluster. Beter is een eigen gebruiker zonder `sudo`, met een kubeconfig die alleen deployments en services in één namespace mag beheren, en de runner niet op de control plane zetten. Ik laat de deploy alleen draaien op `main`, dus niet bij pull requests.

De runner maakt zelf een uitgaande verbinding met GitHub (HTTPS) en haalt de jobs op, dus er hoeft geen poort open naar internet. `kubectl` praat op CN1 lokaal met de API van K3s. Het image komt uit Docker Hub met het pull-secret, en dat secret komt uit GitHub. Het token in dat secret heeft alleen lees-rechten.

## 1.2 Standaarden: ISO 27001, ISO 27002, NIS2 en CIS

ISO 27001 is een norm om informatiebeveiliging in een organisatie te regelen (een ISMS), met 93 maatregelen. ISO 27002 legt uit hoe je die maatregelen invult. NIS2 is een Europese wet die bepaalde organisaties verplicht om maatregelen te nemen en incidenten te melden. In Nederland heet die wet de Cyberbeveiligingswet. De CIS Controls zijn 18 controls met concrete technische maatregelen, in volgorde van wat het eerst moet.

ISO 27001 en NIS2 zeggen vooral wat je moet regelen. CIS zegt wat je technisch kunt doen en waar je het beste mee begint. CIS heeft ook officiële tabellen waarin staat welke CIS-control bij welke maatregel van ISO 27001, ISO 27002 en NIS2 hoort.

Mijn advies voor SolidApps is om eerst uit te zoeken of ze onder NIS2 vallen. Gebruik ISO 27001 als kader en de CIS Controls en CIS Benchmarks voor Kubernetes, Docker en Ubuntu als technische basis. Die controles kunnen automatisch in de pipeline draaien. Leg één keer vast welke maatregel uit NIS2 bij welke ISO- en CIS-maatregel hoort.

Bronnen: [ISO 27001](https://www.iso.org/standard/27001), [ISO 27002](https://www.iso.org/standard/75652.html), [NIS2](https://eur-lex.europa.eu/eli/dir/2022/2555/oj), [CIS Controls](https://www.cisecurity.org/controls/v8), [CIS mapping naar ISO 27001](https://www.cisecurity.org/insights/white-papers/cis-controls-v8-1-mapping-to-iso-iec-27001-2022), [CIS mapping naar NIS2](https://www.cisecurity.org/insights/white-papers/cis-controls-v8-1-mapping-to-nis2-directive-2022-2555).

## 1.3 CVE's en signature-based detectie

CVE's kun je op een paar manieren indelen. Op ernst (CVSS: Low, Medium, High, Critical), op het type zwakte (CWE, zoals SQL-injectie of XSS), op de aanvalsvector (bijvoorbeeld via het netwerk of lokaal) en op waar de fout zit (besturingssysteem, een package, de container runtime of Kubernetes). Ook kun je kijken hoe snel je ze moet aanpakken: staat een CVE op de CISA KEV-lijst, dan wordt hij al misbruikt, en de EPSS-score zegt hoe groot de kans op misbruik is.

Bij signature-based detectie vergelijkt een scanner de packages en versies in een image (de SBOM) met databases met bekende kwetsbaarheden, zoals de NVD en OSV. SolidApps kan dat bij elke build in de pipeline doen, bijvoorbeeld met Docker Scout of Trivy. Omdat er elke dag nieuwe CVE's bijkomen, moeten ze bestaande images ook regelmatig opnieuw scannen. Het nadeel is dat je alleen bekende kwetsbaarheden vindt, dus geen zero-days.

Bronnen: [CVE](https://www.cve.org), [NVD en CVSS](https://nvd.nist.gov/vuln-metrics/cvss), [CWE](https://cwe.mitre.org), [CISA KEV](https://www.cisa.gov/known-exploited-vulnerabilities-catalog), [EPSS](https://www.first.org/epss/), [OSV](https://osv.dev), [Trivy](https://trivy.dev), [Docker Scout](https://docs.docker.com/scout/).
