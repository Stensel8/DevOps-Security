# Week 4 - status

## Gemaakt
- [x] Extra: image ook naar GHCR pushen (`ghcr.io/stensel8/devops-security`), met `GITHUB_TOKEN` i.p.v. een los secret — bewijs nodig: pipeline-run groen + screenshot van het package op GHCR (`https://github.com/Stensel8/DevOps-Security/pkgs/container/devops-security`) na de eerste succesvolle push
- [x] 4.2 Gedocumenteerd dat Docker Hub-login al via twee PAT's gaat (push- en een los read-only pull-token), en waarom dat veiliger is dan een wachtwoord
- [x] 4.3 Multicriteria-analyse ECR vs ACR vs Docker Hub (security/kosten/performance) + advies, incl. welke auth-methode Harbor zou moeten gebruiken met Entra ID
- [x] 4.4 De Docker Hub secrets-lek van december 2025 (Flare-onderzoek) geanalyseerd tegen onze eigen PoC, advies voor SolidApps

## Nog te doen
- [ ] 4.1 Eigen Harbor-registry installeren (minimale install, self-signed TLS-cert), push/pull-bewijs, auth-methodes van Harbor beschrijven — wacht op een draaiend cluster. Script staat klaar: [`kubernetes/harbor/install-harbor.sh`](../kubernetes/harbor/install-harbor.sh) (shellcheck-schoon). Op een **losse derde instance** draaien, niet op CN1/CN2: Harbor's eigen docker-compose-stack (registry, portal, core, redis, postgres) wil niet concurreren met K3s op een t2.medium.
  ```bash
  sudo ./kubernetes/harbor/install-harbor.sh <public-ip-of-dns-van-de-instance> <eigen-wachtwoord>
  ```

---
Hier houd ik bij wat ik nog moet doen.
