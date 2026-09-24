# Week 3

## 3.2 Docker Scout

Als ik het image in de beginstaat bouw, is het al best kwetsbaar. Docker Scout laat meteen alles zien: 96 kwetsbaarheden, waarvan 3 Critical en 21 High. Het meeste zit in de basisimage (`python:3-slim-bookworm`), maar in onze eigen lagen zitten ook 9 High. Zie de screenshots.

![Build van het image in de beginstaat](images/github-actions-build.png)
![Docker Scout op Docker Hub](images/docker-scout.png)

Trivy telt anders, die komt op 98 High of Critical. Scanners gebruiken andere databases en tellen anders. Van die 98 zitten er 96 in de Debian-basislaag, waarvoor nog geen fix bestaat, en 2 in Python-packages van Poetry, waarvoor wel een fix is.
