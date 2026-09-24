# DevOps Security

[![Docker Hub](https://img.shields.io/badge/Docker%20Hub-stensel8%2Fdevops--security-2496ED?logo=docker&logoColor=white)](https://hub.docker.com/r/stensel8/devops-security)
[![Image size](https://img.shields.io/docker/image-size/stensel8/devops-security/latest?label=image&logo=docker&logoColor=white)](https://hub.docker.com/r/stensel8/devops-security)
[![Docker Scout](https://img.shields.io/badge/Docker%20Scout-0%20CVE's-brightgreen?logo=docker&logoColor=white)](week-3/README.md#alle-kwetsbaarheden-fixen)
[![CI/CD](https://github.com/Stensel8/DevOps-Security/actions/workflows/build.yaml/badge.svg)](https://github.com/Stensel8/DevOps-Security/actions/workflows/build.yaml)
[![CodeQL](https://github.com/Stensel8/DevOps-Security/actions/workflows/dynamic/github-code-scanning/codeql/badge.svg)](https://github.com/Stensel8/DevOps-Security/security/code-scanning)

Een Flask-app (Quoter XP) waar bewust kwetsbaarheden in zitten, met een pipeline van GitHub Actions naar Docker Hub en een K3s-cluster op AWS. Het idee is om dit helemaal aan te passen en te gaan beveiligen.

- [Casus](case/README.md)
- [Week 1](week-1/README.md): bootomgeving, standaarden en CVE's
- [Week 2](week-2/README.md): Snyk, SQL-injectie en XSS fixen, advies voor developers
- [Week 3](week-3/README.md): Docker Scout en het image kwetsbaarheidsvrij maken
