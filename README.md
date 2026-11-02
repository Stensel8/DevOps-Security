# DevOps Security

[![Docker Hub](https://img.shields.io/badge/Docker%20Hub-stensel8%2Fdevops--security-2496ED?logo=docker&logoColor=white)](https://hub.docker.com/r/stensel8/devops-security)
[![Image size](https://img.shields.io/docker/image-size/stensel8/devops-security/latest?label=image&logo=docker&logoColor=white)](https://hub.docker.com/r/stensel8/devops-security)
[![GHCR](https://img.shields.io/badge/GHCR-stensel8%2Fdevops--security-2496ED?logo=github&logoColor=white)](https://github.com/Stensel8/DevOps-Security/pkgs/container/devops-security)
[![CodeTrunk mirror](https://img.shields.io/badge/mirror-CodeTrunk%20(EU)-2496ED)](https://repos.codetrunk.eu/Stensel8/DevOps-Security)
[![CI/CD](https://github.com/Stensel8/DevOps-Security/actions/workflows/build.yaml/badge.svg)](https://github.com/Stensel8/DevOps-Security/actions/workflows/build.yaml)
[![CodeQL](https://github.com/Stensel8/DevOps-Security/actions/workflows/dynamic/github-code-scanning/codeql/badge.svg)](https://github.com/Stensel8/DevOps-Security/security/code-scanning)

Mijn uitwerking van de casus. De basis is een Flask-app (Quoter XP) met bewust ingebouwde kwetsbaarheden, een pipeline van GitHub Actions naar Docker Hub (en sinds week 4 ook GHCR) en een K3s-cluster op AWS. Die beveilig ik stap voor stap. Elke week-map heeft naast de uitwerking (`README.md`) ook een `TODO.md` met wat er nog gedaan moet worden. Installatiehandleiding voor de AWS-omgeving: [`setup/README.md`](setup/README.md).

Ik werk hierbij met AI-assistentie, via IDE-integraties. De opzet, keuzes en het testen zijn van mij, maar een deel van het typewerk en het debuggen doe ik samen met deze tools. In de screencast bij [week 3](week-3/README.md) is dat ook terug te zien.

- Anthropic. (2026). *Claude (Sonnet 5)* [Large language model]. [https://claude.ai](https://claude.ai)
- Mistral AI. (2026). *Mistral Vibe (GLM 5.3)* [Large language model]. [https://mistral.ai](https://mistral.ai)

**PDF/ODT-export van deze portfolio.** Bij elke push naar `main` zet een GitHub Actions-workflow ([`.github/workflows/docs.yml`](.github/workflows/docs.yml)) automatisch een PDF en een ODT klaar met alle informatie uit de repo, als assets bij een nieuwe [release](../../releases). Ik heb deze exports dus niet zelf handmatig gemaakt; ze worden automatisch gegenereerd vanuit de README's via [`setup/export-portfolio.sh`](setup/export-portfolio.sh) (pandoc + typst).

De repository staat ook gespiegeld op [CodeTrunk](https://repos.codetrunk.eu/Stensel8/DevOps-Security), een Europese Git-host met IPv6-ondersteuning: voor redundantie en omdat ik niet alles alleen op GitHub (VS) wil hebben staan.

- [Casus](case/README.md)
- [Week 1](week-1/README.md): bootomgeving, standaarden en CVE's
- [Week 2](week-2/README.md): Snyk, SQL-injectie en XSS fixen, advies voor developers
- [Week 3](week-3/README.md): Docker Scout en het image kwetsbaarheidsvrij maken
- [Week 4](week-4/README.md): registry-beveiliging, eigen Harbor-install
- [Week 5](week-5/README.md): CIS-hardening met kube-bench, Ingress met TLS, NetworkPolicy
- [Week 6](week-6/README.md): monitoring met Prometheus, traceability met Trivy, pentest-advies
- [Week 7](week-7/README.md): OS-hardening van de nodes, ServiceAccount en RBAC
