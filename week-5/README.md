# Week 5: Kubernetes hardenen

In deze week staat de beveiliging van het Kubernetes-cluster zelf centraal. Een standaardinstallatie van Kubernetes werkt direct, maar is niet op alle punten veilig ingesteld. Hardenen betekent dat die instellingen strenger worden gemaakt, zodat een aanvaller minder mogelijkheden heeft.

Voor het hardenen van Kubernetes bestaat de CIS Kubernetes Benchmark: een lijst met aanbevolen instellingen voor de onderdelen van een cluster [(Center for Internet Security, z.d.)](https://www.cisecurity.org/benchmark/kubernetes). Daarnaast hebben de NSA en CISA een richtlijn gepubliceerd die onder andere ingaat op de beveiliging van pods, netwerkscheiding, authenticatie en autorisatie, en audit logging [(National Security Agency & Cybersecurity and Infrastructure Security Agency, 2022)](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF).

Deze week bestaat uit vier opdrachten. Paragraaf 5.1 beschrijft de controle van het cluster met kube-bench en drie maatregelen uit de benchmark. Paragraaf 5.2 gaat over een Ingress met TLS, en paragraaf 5.3 over het netwerkplugin van K3s en de vraag of dat veilig genoeg is. Paragraaf 5.4 beschrijft hoe SolidApps toegang kan regelen zonder gedeeld adminwachtwoord.

## 5.1 kube-bench: nulmeting en drie maatregelen

Voor deze opdracht heb ik kube-bench gebruikt. kube-bench is een tool van Aqua Security die een cluster automatisch controleert op de aanbevelingen uit de CIS Kubernetes Benchmark [(Aqua Security, z.d.)](https://github.com/aquasecurity/kube-bench). Een aparte CIS-benchmark voor K3s bestaat niet: K3s wordt getoetst aan de gewone CIS Kubernetes Benchmark. Wel heeft kube-bench een eigen configuratie voor K3s. Die is nodig omdat K3s de onderdelen van Kubernetes anders inricht dan een standaardinstallatie. Ze draaien samen in het k3s-proces, met andere bestandspaden; etcd zit bijvoorbeeld in het k3s-proces zelf [(K3s Project Authors, z.d.-b)](https://docs.k3s.io/security/self-assessment-1.8). Met de standaardconfiguratie vindt kube-bench die onderdelen niet.

De nulmeting op CN1, de control plane, gaf het volgende resultaat:

```
54 checks PASS, 5 checks FAIL, 57 checks WARN, 14 checks INFO
```

De vijf meldingen met FAIL gingen onder andere over de rechten op certificaatbestanden en een paar punten in RBAC. Voor de opdracht heb ik drie maatregelen toegepast, uit drie verschillende onderdelen van de benchmark.

### Onderdeel 5.7: algemene policies

De aanbevelingen 5.7.2 (een seccomp-profiel voor pods) en 5.7.3 (een SecurityContext voor pods en containers) waren al ingevoerd in week 2, bij fix 6. In [kubernetes/deployment.yaml](../kubernetes/deployment.yaml) staan onder andere `seccompProfile: RuntimeDefault`, `runAsNonRoot` en `allowPrivilegeEscalation: false`. kube-bench blijft deze punten als WARN melden, omdat het handmatige controles zijn die een mens moet beoordelen. De instellingen staan er wel.

### Onderdeel 5.2: Pod Security Standards

Kubernetes kent drie Pod Security Standards: privileged, baseline en restricted. Restricted is het strengste niveau en volgt de best practices voor het hardenen van pods [(The Kubernetes Authors, z.d.-c)](https://kubernetes.io/docs/concepts/security/pod-security-standards/). Ik heb het niveau restricted verplicht gemaakt voor de namespace `default`, met een label op de namespace. De bestaande pod bleef gewoon draaien, omdat die al aan de eisen voldeed. Een bewust onveilige testpod werd direct geweigerd:

```
Error from server (Forbidden): pods "privtest" is forbidden: violates PodSecurity "restricted:latest":
privileged (container "privtest" must not set securityContext.privileged=true), ...
```

### Onderdeel 3.2: audit logging

Audit logging legt vast welke verzoeken er bij de API-server van Kubernetes binnenkomen: wie deed wat, en wanneer [(The Kubernetes Authors, z.d.-a)](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/). K3s logde dat standaard niet. Met [kubernetes/audit-policy.yaml](../kubernetes/audit-policy.yaml) heb ik audit logging aangezet. Het beleid maakt onderscheid tussen soorten verzoeken:

- **Commando's in een pod en wijzigingen in RBAC** worden volledig gelogd, met het verzoek en het antwoord. Met deze acties kan een aanvaller het verst komen.
- **Secrets en configmaps** worden alleen op metadataniveau gelogd. Zo komt de inhoud van een secret niet in het logbestand terecht.
- **De overige verzoeken** worden ook op metadataniveau gelogd.

Na een herstart van K3s bleef het cluster op Ready, en bleef de app bereikbaar. Ik heb gecontroleerd dat een commando in een pod volledig in het log komt, en dat bij het opvragen van een secret alleen de metadata wordt gelogd.

Na de maatregelen heb ik kube-bench opnieuw gedraaid:

```
59 checks PASS, 5 checks FAIL, 52 checks WARN, 14 checks INFO
```

Vijf controles gingen van WARN naar PASS: 1.2.16 tot en met 1.2.19, over het pad, de bewaartermijn en de grootte van het auditlog, en 3.2.1, die controleert of er een auditbeleid is. Controle 3.2.2 blijft op WARN, omdat kube-bench die altijd door een mens laat beoordelen.

### Extra: de containerd-socket

De CIS Kubernetes Benchmark zegt niets over de rechten op de socket van containerd, de container runtime van K3s. Wie die socket kan gebruiken, kan containers starten en stoppen op de node, en komt zo om de maatregelen hierboven heen. Ik heb daarom gecontroleerd dat de socket alleen bereikbaar is voor root. Dat stond al goed, waardoor hier niets hoefde te worden aangepast.

## 5.2 Ingress met TLS-terminatie op een andere poort dan 443

Een Ingress regelt hoe verkeer van buiten het cluster bij de juiste service terechtkomt. K3s heeft daarvoor Traefik al ingebouwd als Ingress-controller. Met ServiceLB, de eigen load balancer van K3s, krijgt de service van Traefik een poort op elke node [(K3s Project Authors, z.d.-c)](https://docs.k3s.io/networking/networking-services). In mijn cluster zijn dat NodePort 31985 voor HTTP en 31189 voor HTTPS. Een aparte Ingress-controller was daardoor niet nodig.

Voor de TLS-verbinding heb ik een self-signed certificaat gemaakt en als secret in het cluster gezet. Daarna heb ik de Ingress uit [kubernetes/ingress.yaml](../kubernetes/ingress.yaml) toegepast. Een test op HTTPS-poort 31189 laat zien dat de verbinding met TLS 1.3 wordt opgezet, met het eigen certificaat:

```
* SSL connection using TLSv1.3 / TLS_AES_128_GCM_SHA256
*   subject: CN=quoterxp.local
< HTTP/2 200
```

Traefik doet hier de TLS-terminatie, ook wel SSL-offloading genoemd. De verbinding van buiten is versleuteld tot aan Traefik. Van Traefik naar de pod gaat het verkeer via HTTP op poort 5000, binnen het cluster.

Om dit ook van buiten het cluster te testen, moest poort 31189 open in de security group. Daarbij zag ik dat NodePort 30000, de app uit week 1, op dat moment openstond voor heel internet, en niet alleen voor mijn eigen IP-adres. Dat heb ik direct rechtgezet: poort 30000 staat nu alleen open voor mijn eigen IP-adres, net als SSH, en de nieuwe regels voor 31189 en 6443 ook. Daarna gaf ook een test vanaf mijn laptop HTTP 200.

![De security group: 30000, 6443 en 31189 alleen open voor mijn eigen IP-adres](images/security-group-eigen-ip.png)

## 5.3 Welke CNI gebruikt K3s, en is dat veilig genoeg?

Een CNI-plugin (container network interface) zorgt voor het netwerk tussen de pods. K3s gebruikt standaard Flannel, met VXLAN als techniek om verkeer tussen de nodes te versturen [(K3s Project Authors, z.d.-a)](https://docs.k3s.io/networking/basic-network-options). Flannel regelt alleen dat pods op verschillende nodes elkaar kunnen bereiken. Het dwingt zelf geen regels af over welk verkeer is toegestaan.

Daarvoor heeft K3s een eigen network-policy-controller ingebouwd, die gebruikmaakt van de bibliotheek van kube-router. Die controller voert NetworkPolicy-objecten wel uit, tenzij K3s wordt gestart met `--disable-network-policy` [(K3s Project Authors, z.d.-c)](https://docs.k3s.io/networking/networking-services). Bij mijn cluster staat die optie niet aan.

Een andere CNI kiezen kan, maar niet terwijl het cluster draait: het cluster moet dan opnieuw worden opgezet met een andere CNI, zoals Calico of Cilium. Cilium gebruikt eBPF, kan regels maken op het niveau van de applicatie, en geeft met Hubble inzicht in het netwerkverkeer [(Cilium Authors, z.d.)](https://docs.cilium.io/en/stable/overview/intro/).

Voor een cluster van deze omvang, met twee nodes, is de ingebouwde controller van K3s voldoende. Bij een groter cluster met meerdere teams en namespaces adviseer ik Cilium, vooral vanwege de regels op applicatieniveau en het inzicht in het verkeer.

### NetworkPolicy: alleen poort 5000

Een NetworkPolicy bepaalt welk verkeer een pod mag ontvangen of versturen. Zodra een pod door een NetworkPolicy wordt geselecteerd, wordt al het verkeer geblokkeerd dat niet expliciet is toegestaan [(The Kubernetes Authors, z.d.-b)](https://kubernetes.io/docs/concepts/services-networking/network-policies/). De policy in [kubernetes/networkpolicy.yaml](../kubernetes/networkpolicy.yaml) selecteert de pods van Quoter XP en staat alleen inkomend verkeer op poort 5000 toe. Met een tijdelijke testpod heb ik gecontroleerd dat poort 5000 bereikbaar is en een andere poort niet:

```
devops-security (10.43.166.211:5000) open
nc: devops-security (10.43.166.211:9999): Connection timed out
```

Daarmee is ook de vraag uit deze paragraaf beantwoord: de ingebouwde controller van K3s dwingt de NetworkPolicy echt af, ook al is Flannel zelf alleen een overlaynetwerk.

## 5.4 Toegang zonder adminwachtwoord

SolidApps zou een omgeving als deze uitrollen met Terraform en Ansible, in plaats van met losse scripts zoals in deze proefopstelling. In deze paragraaf beschrijf ik hoe de toegang daarbij kan worden geregeld zonder gedeeld adminwachtwoord.

- **SSH naar de servers:** elke engineer krijgt een eigen sleutelpaar in plaats van een gedeelde login. Op AWS is Session Manager van Systems Manager nog beter: er hoeft dan geen SSH-poort open te staan, en IAM regelt de toegang [(Amazon Web Services, z.d.)](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html).
- **De state van Terraform:** die staat in een S3-bucket, met een bucket policy die alleen de juiste IAM-rol toegang geeft [(HashiCorp, z.d.)](https://developer.hashicorp.com/terraform/language/backend/s3). Dat is belangrijk, omdat de state gevoelige gegevens kan bevatten.
- **De pipeline:** de pipeline die `terraform apply` draait, logt bij AWS in met een IAM-rol via OIDC. Hij krijgt dan per run een tijdelijk token, in plaats van een vaste access key in een secret [(GitHub, z.d.)](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).
- **Ansible:** de inventory en playbooks gebruiken sleutels in plaats van wachtwoorden. Gevoelige gegevens in playbooks, zoals API-sleutels, worden versleuteld met Ansible Vault [(Ansible Community, z.d.)](https://docs.ansible.com/ansible/latest/vault_guide/index.html).
- **De nodes zelf:** elke engineer heeft een eigen account met een eigen sleutel, en het gebruik van `sudo` wordt per gebruiker gelogd met `auditd`.

Dit is hetzelfde principe als in mijn adviezen in week 2 en 4: één eigen identiteit per persoon of systeem, in plaats van een gedeeld geheim dat bij een lek overal moet worden vervangen.

### TryHackMe: Cluster Hardening

Als onderdeel van deze opdracht heb ik de room "Cluster Hardening" op TryHackMe volledig doorlopen, inclusief de praktische opdracht [(TryHackMe, z.d.)](https://tryhackme.com/room/clusterhardening).

![De room Cluster Hardening op TryHackMe: 100% voltooid](images/tryhackme-cluster-hardening-voltooid.png)

De drie belangrijkste lessen uit de room, vertaald naar SolidApps:

1. **TLS op al het verkeer tussen de onderdelen van de control plane.** De API-server communiceert met bijna alles in het cluster, zoals de kubelet en etcd. Is dat verkeer niet versleuteld, dan kan iemand die al in het netwerk zit meekijken, of zich voordoen als een van die onderdelen.
2. **RBAC met least privilege.** Een service account krijgt alleen de rechten die het echt nodig heeft. Een overgenomen pod met te veel rechten kan anders het hele cluster overnemen. In week 7 pas ik dit toe.
3. **Admission controllers.** Een admission controller werkt als een portier bij de ingang van het cluster. Voordat een pod mag starten, controleert hij of de pod aan de regels voldoet. Voldoet de pod niet, dan start hij niet. Dat was in 5.1 te zien: de onveilige testpod werd door Pod Security Admission geweigerd.

## Bronnen

Amazon Web Services. (z.d.). *AWS Systems Manager Session Manager*. AWS Systems Manager User Guide. https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html

Ansible Community. (z.d.). *Protecting sensitive data with Ansible vault*. Ansible Community Documentation. https://docs.ansible.com/ansible/latest/vault_guide/index.html

Aqua Security. (z.d.). *kube-bench* \[Broncode\]. GitHub. https://github.com/aquasecurity/kube-bench

Center for Internet Security. (z.d.). *CIS Kubernetes Benchmarks*. https://www.cisecurity.org/benchmark/kubernetes

Cilium Authors. (z.d.). *Introduction to Cilium & Hubble*. Cilium documentation. https://docs.cilium.io/en/stable/overview/intro/

GitHub. (z.d.). *Configuring OpenID Connect in Amazon Web Services*. GitHub Docs. https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws

HashiCorp. (z.d.). *Backend type: s3*. Terraform documentation. https://developer.hashicorp.com/terraform/language/backend/s3

K3s Project Authors. (z.d.-a). *Basic network options*. K3s. https://docs.k3s.io/networking/basic-network-options

K3s Project Authors. (z.d.-b). *CIS 1.8 self assessment guide*. K3s. https://docs.k3s.io/security/self-assessment-1.8

K3s Project Authors. (z.d.-c). *Networking services*. K3s. https://docs.k3s.io/networking/networking-services

National Security Agency & Cybersecurity and Infrastructure Security Agency. (2022). *Kubernetes hardening guide* (Versie 1.2). https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF

The Kubernetes Authors. (z.d.-a). *Auditing*. Kubernetes. https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/

The Kubernetes Authors. (z.d.-b). *Network policies*. Kubernetes. https://kubernetes.io/docs/concepts/services-networking/network-policies/

The Kubernetes Authors. (z.d.-c). *Pod Security Standards*. Kubernetes. https://kubernetes.io/docs/concepts/security/pod-security-standards/

TryHackMe. (z.d.). *Cluster hardening*. https://tryhackme.com/room/clusterhardening
