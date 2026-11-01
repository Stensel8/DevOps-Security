# Week 4 - status

## Gemaakt
- [x] Extra: image ook naar GHCR pushen (`ghcr.io/stensel8/devops-security`), met `GITHUB_TOKEN` i.p.v. een los secret — bewijs nodig: pipeline-run groen + screenshot van het package op GHCR (`https://github.com/Stensel8/DevOps-Security/pkgs/container/devops-security`) na de eerste succesvolle push
- [x] 4.2 Gedocumenteerd dat Docker Hub-login al via twee PAT's gaat (push- en een los read-only pull-token), en waarom dat veiliger is dan een wachtwoord
- [x] 4.3 Multicriteria-analyse ECR vs ACR vs Docker Hub (security/kosten/performance) + advies, incl. welke auth-methode Harbor zou moeten gebruiken met Entra ID
- [x] 4.4 De Docker Hub secrets-lek van december 2025 (Flare-onderzoek) geanalyseerd tegen onze eigen PoC, advies voor SolidApps
- [x] 4.1 Harbor geïnstalleerd via EC2 user-data (`kubernetes/harbor/harbor-userdata.sh`) op een losse instance, self-signed TLS, ingelogd als admin

## Nog te doen
- [ ] 4.1 Push/pull-bewijs: een image van Docker Hub naar Harbor pushen en weer terugtrekken, met screenshot in de Harbor-UI. Harbor's cert moet eerst lokaal vertrouwd worden (`/etc/docker/certs.d/<host>/ca.crt`) voor `docker push` het accepteert.
- [ ] 4.1 Auth-methodes van Harbor beschrijven (los van wat al in 4.3 staat over OIDC/Entra ID)

---
Hier houd ik bij wat ik nog moet doen.
