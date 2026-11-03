# Week 7: OS-hardening en RBAC

In deze laatste week staan twee lagen centraal die nog niet aan bod zijn gekomen: het besturingssysteem van de nodes, en de rechten van accounts binnen het cluster. Ook als de containers en het cluster goed zijn ingesteld, kan een zwak ingesteld besturingssysteem of een account met te veel rechten een aanvaller alsnog toegang geven tot de hele omgeving.

Voor het besturingssysteem gebruik ik de CIS Ubuntu Linux Benchmark, met aanbevelingen voor een veilige inrichting van Ubuntu [(Center for Internet Security, z.d.-b)](https://www.cisecurity.org/benchmark/ubuntu_linux). Binnen het cluster regelt RBAC (role-based access control) wie wat mag. Met een Role of ClusterRole wordt vastgelegd welke acties zijn toegestaan op welke soorten objecten, en met een binding worden die rechten gekoppeld aan een gebruiker of service account [(The Kubernetes Authors, z.d.-c)](https://kubernetes.io/docs/reference/access-authn-authz/rbac/).

Deze week bestaat uit drie opdrachten. Paragraaf 7.1 beschrijft het hardenen van het besturingssysteem van CN1 en CN2. Paragraaf 7.2 gaat over een service account met alleen de rechten die het nodig heeft, en paragraaf 7.3 beschrijft hoe SolidApps een toekomstige Windows-node kan hardenen.

## 7.1 OS-hardening op CN1 en CN2

De nodes draaien Ubuntu 26.04 LTS. Ik heb drie maatregelen uit de CIS-benchmark toegepast, uit drie verschillende onderdelen, op beide nodes. De nummers en levels hieronder komen uit de CIS Ubuntu Linux 24.04 LTS Benchmark, zoals die zijn overgenomen door Ansible Lockdown, een open-source project dat de benchmark automatiseert [(Ansible Lockdown, z.d.)](https://github.com/ansible-lockdown/UBUNTU24-CIS). Twee van de drie maatregelen zijn Level 2: het uitschakelen van `udf` en de auditregel op sudoers. De instellingen voor SSH zijn Level 1.

| Maatregel | CIS-aanbeveling | Level |
| --- | --- | --- |
| Kernelmodule `cramfs` uitschakelen | 1.1.1.1 | 1 |
| Kernelmodule `udf` uitschakelen | 1.1.1.8 | 2 |
| auditd installeren en aanzetten | 6.2.1.1 en 6.2.1.2 | 2 |
| Wijzigingen aan sudoers loggen | 6.2.3.1 | 2 |
| SSH: maximaal vier inlogpogingen | 5.1.16 | 1 |
| SSH: inloggen als root uitschakelen | 5.1.20 | 1 |

### Ongebruikte bestandssystemen uitschakelen

De eerste maatregel komt uit het onderdeel over bestandssystemen. De kernelmodules voor `cramfs` en `udf` worden op deze servers niet gebruikt. Een kwetsbaarheid in zo'n weinig gebruikte module vergroot het aanvalsoppervlak zonder dat het iets oplevert. Met een regel in `/etc/modprobe.d/` wordt het laden van de module geblokkeerd [(Canonical, z.d.-b)](https://manpages.ubuntu.com/manpages/noble/man5/modprobe.d.5.html), bijvoorbeeld met `install udf /bin/false`.

### Wijzigingen aan sudoers loggen met auditd

De tweede maatregel komt uit het onderdeel over logging en auditing. auditd is het auditsysteem van Linux: het legt op basis van regels vast welke acties er op het systeem worden uitgevoerd [(Canonical, z.d.-a)](https://manpages.ubuntu.com/manpages/noble/man8/auditctl.8.html). Ik heb auditd geïnstalleerd met een regel die elke schrijfactie en elke wijziging van de rechten op `/etc/sudoers` logt. In dat bestand staat wie beheerdersrechten heeft, dus een wijziging daarin wil je altijd terugzien. Om de regel te testen heb ik de rechten van het bestand opnieuw ingesteld, zonder de inhoud te veranderen. Het auditlog laat zien welke gebruiker dat deed:

```
-w /etc/sudoers -p wa -k sudoers_wijziging
type=SYSCALL ... comm="chmod" ... key="sudoers_wijziging" ... AUID="ubuntu" UID="root"
```

Het veld `AUID` laat zien dat de gebruiker `ubuntu` de actie uitvoerde, ook al gebeurde het met rootrechten via `sudo`.

### SSH strenger instellen

De derde maatregel komt uit het onderdeel over SSH. Inloggen als root is nu uitgeschakeld, en per verbinding zijn maximaal vier inlogpogingen toegestaan [(OpenBSD Project, z.d.)](https://man.openbsd.org/sshd_config).

Na de maatregelen heb ik op beide nodes gecontroleerd dat alles nog werkt. Daarvoor heb ik een nieuwe SSH-sessie geopend in plaats van de bestaande te gebruiken, omdat je anders niet merkt dat je jezelf hebt buitengesloten. Inloggen lukte, en beide nodes bleven op Ready staan.

## 7.2 ServiceAccount met least-privilege RBAC

Een service account is een identiteit voor een programma in plaats van een mens, bijvoorbeeld voor een pod die met de API van Kubernetes moet communiceren [(The Kubernetes Authors, z.d.-b)](https://kubernetes.io/docs/concepts/security/service-accounts/). Voor deze opdracht heb ik in [kubernetes/pod-reader-rbac.yaml](../kubernetes/pod-reader-rbac.yaml) een service account `pod-reader` gemaakt, met een ClusterRole die alleen `get` en `list` op pods toestaat. Met `kubectl create token pod-reader` heb ik er een tijdelijk token voor aangemaakt.

Met dat token heb ik vanaf mijn eigen laptop de API van het cluster aangesproken, met HTTPie, een programma om API's te testen [(HTTPie, z.d.)](https://httpie.io/). Poort 6443 staat sinds week 5 open voor mijn eigen IP-adres. Het opvragen van pods is toegestaan, en geeft HTTP 200 met de gegevens van de pod:

![HTTPie: het opvragen van pods geeft 200](images/httpie-pods-200.png)

Het opvragen van namespaces staat niet in de ClusterRole, en geeft een 403 zonder gegevens:

![HTTPie: het opvragen van namespaces geeft 403 Forbidden](images/httpie-namespaces-403.png)

```
namespaces is forbidden: User "system:serviceaccount:default:pod-reader" cannot list resource "namespaces"
```

Het service account kan dus precies doen waarvoor het bedoeld is, en niets anders. Als dit token ooit uitlekt, kan een aanvaller er alleen de lijst met pods mee opvragen.

## 7.3 Een toekomstige Windows worker-node hardenen

Als SolidApps ooit Windows-containers nodig heeft, bijvoorbeeld voor een applicatie op .NET Framework, komt er een Windows worker-node bij. Kubernetes ondersteunt Windows-nodes als worker [(The Kubernetes Authors, z.d.-d)](https://kubernetes.io/docs/concepts/windows/intro/). Windows is een andere familie van besturingssystemen, met een eigen benchmark en eigen aandachtspunten. In deze paragraaf beschrijf ik de maatregelen die ik zou toepassen.

- **De CIS-benchmark voor Windows Server:** in plaats van de Ubuntu-benchmark uit 7.1 geldt hier de CIS Microsoft Windows Server Benchmark [(Center for Internet Security, z.d.-a)](https://www.cisecurity.org/benchmark/microsoft_windows_server).
- **Unieke lokale beheerderswachtwoorden met LAPS:** Windows LAPS beheert het wachtwoord van het lokale beheerdersaccount per server [(Microsoft, 2026)](https://learn.microsoft.com/en-us/windows-server/identity/laps/laps-overview). Zo deelt niet elke node hetzelfde wachtwoord.
- **SMBv1 niet gebruiken:** SMBv1 is een verouderd protocol voor het delen van bestanden. Microsoft raadt af om het opnieuw te installeren, en adviseert in plaats daarvan systemen bij te werken die het nog nodig hebben [(Microsoft, 2025a)](https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3). Op een Kubernetes-node is het niet nodig.
- **Een minimale firewall:** net als bij de security group in week 1 staan alleen de poort van de kubelet en de NodePorts open, en de rest is dicht.
- **Geen wachtwoorden in containers:** als een container toegang nodig heeft tot Active Directory, gebruik dan een group Managed Service Account (gMSA) [(The Kubernetes Authors, z.d.-a)](https://kubernetes.io/docs/tasks/configure-pod-container/configure-gmsa/). Dat is hetzelfde principe als in 4.4: geen secrets in een image.
- **Containers veilig inrichten:** Microsoft beschrijft hoe Windows-containers veilig kunnen worden ingericht [(Microsoft, 2025b)](https://learn.microsoft.com/en-us/virtualization/windowscontainers/manage-containers/container-security). Die richtlijnen zou ik als basis nemen.
- **Een vast patchbeleid:** Windows-updates worden op een vast moment geïnstalleerd, eerst op een deel van de nodes en daarna op de rest, met dezelfde opvolging van kwetsbaarheden als in 1.3.

## Bronnen

Ansible Lockdown. (z.d.). *UBUNTU24-CIS* \[Broncode\]. GitHub. https://github.com/ansible-lockdown/UBUNTU24-CIS

Canonical. (z.d.-a). *auditctl: A utility to assist controlling the kernel's audit system*. Ubuntu Manpages. https://manpages.ubuntu.com/manpages/noble/man8/auditctl.8.html

Canonical. (z.d.-b). *modprobe.d: Configuration directory for modprobe*. Ubuntu Manpages. https://manpages.ubuntu.com/manpages/noble/man5/modprobe.d.5.html

Center for Internet Security. (z.d.-a). *CIS Microsoft Windows Server Benchmarks*. https://www.cisecurity.org/benchmark/microsoft_windows_server

Center for Internet Security. (z.d.-b). *CIS Ubuntu Linux Benchmarks*. https://www.cisecurity.org/benchmark/ubuntu_linux

HTTPie. (z.d.). *HTTPie: API testing client that flows with you*. https://httpie.io/

Microsoft. (2025a, 28 februari). *Detect, enable, and disable SMBv1, SMBv2, and SMBv3 in Windows*. Microsoft Learn. https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3

Microsoft. (2025b, 23 januari). *Secure Windows containers*. Microsoft Learn. https://learn.microsoft.com/en-us/virtualization/windowscontainers/manage-containers/container-security

Microsoft. (2026, 14 september). *Windows LAPS overview*. Microsoft Learn. https://learn.microsoft.com/en-us/windows-server/identity/laps/laps-overview

OpenBSD Project. (z.d.). *sshd_config(5)*. OpenBSD manual pages. https://man.openbsd.org/sshd_config

The Kubernetes Authors. (z.d.-a). *Configure GMSA for Windows pods and containers*. Kubernetes. https://kubernetes.io/docs/tasks/configure-pod-container/configure-gmsa/

The Kubernetes Authors. (z.d.-b). *Service accounts*. Kubernetes. https://kubernetes.io/docs/concepts/security/service-accounts/

The Kubernetes Authors. (z.d.-c). *Using RBAC authorization*. Kubernetes. https://kubernetes.io/docs/reference/access-authn-authz/rbac/

The Kubernetes Authors. (z.d.-d). *Windows containers in Kubernetes*. Kubernetes. https://kubernetes.io/docs/concepts/windows/intro/
