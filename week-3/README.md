# Week 3

## 3.2 Docker Scout

Als ik het image in de beginstaat bouw, is het al best kwetsbaar. Docker Scout laat meteen alles zien: 96 kwetsbaarheden, waarvan 3 Critical en 21 High. Het meeste zit in de basisimage (`python:3-slim-bookworm`), maar in onze eigen lagen zitten ook 9 High. Zie de screenshots.

![Build van het image in de beginstaat](images/github-actions-build.png)
![Docker Scout op Docker Hub](images/docker-scout.png)

Trivy telt anders, die komt op 98 High of Critical. Scanners gebruiken andere databases en tellen anders. Van die 98 zitten er 96 in de Debian-basislaag, waarvoor nog geen fix bestaat, en 2 in Python-packages van Poetry, waarvoor wel een fix is.

### Alle kwetsbaarheden fixen

Daarna heb ik geprobeerd om alle kwetsbaarheden uit het image te halen. Docker Scout liet zien dat de basisimage `python:3-slim-bookworm` (Debian) zelf al 3 Critical en 15 High had, waarvoor vaak geen fix beschikbaar is, en dat onze eigen laag met `apt-get install pipx` er nog 9 High bij deed.

![Docker Scout voor de fix](images/docker-scout-voor.png)

Ik heb de Dockerfile daarom aangepast (commit [`790a9b8`](https://github.com/Stensel8/DevOps-Security/commit/790a9b8)). Ik gebruik nu `python:3.14-alpine` als basis in plaats van Debian. Ook bouw ik in twee stappen (multi-stage): Poetry en pip staan alleen in de bouwstap en niet meer in het image dat draait. Pip heb ik ook uit het eindimage gehaald, want die had oude gebundelde onderdelen (msgpack en setuptools) waar de scanner over klaagde, en de app heeft pip niet nodig om te draaien. Het image draait ook niet meer als root, maar als gebruiker 10001.

Eerst heb ik lokaal met Trivy een paar basisimages vergeleken: Debian bookworm had er 255, Debian trixie 159, Alpine 3 en Chainguard 0. Alpine en Chainguard kwamen allebei op 0 uit, zodra pip eruit was. Ik heb Alpine gekozen, want dat is het bekendste.

```dockerfile
# Bouwen: hier staan Poetry en pip. Dit blijft in de builder en komt niet in het eindimage.
FROM python:3.14-alpine@sha256:9e9fde4d32eedce0b661d9ab91e826b62dddf28e928c230ec55f1866cac66b01 AS builder

WORKDIR /app

# Poetry in een eigen venv, zodat het niet mee gaat naar het eindimage
RUN python -m venv /opt/poetry && /opt/poetry/bin/pip install --no-cache-dir poetry==2.5.1

# Alleen de dependencies uit poetry.lock, in de venv van de app (zonder pip)
RUN python -m venv --without-pip /app/venv
COPY content/pyproject.toml content/poetry.lock ./
RUN VIRTUAL_ENV=/app/venv /opt/poetry/bin/poetry install --no-root --only main --no-interaction --no-ansi

# Draaien: geen Poetry, geen pip, geen build-tools en niet als root
FROM python:3.14-alpine@sha256:9e9fde4d32eedce0b661d9ab91e826b62dddf28e928c230ec55f1866cac66b01

ENV PATH="/app/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN pip uninstall -y pip \
    && addgroup -S -g 10001 app \
    && adduser -S -u 10001 -G app -h /app app

# De app-map moet van de gebruiker zijn: SQLite en het logbestand schrijven hier
COPY --chown=10001:10001 content/ /app/
COPY --from=builder /app/venv /app/venv

WORKDIR /app
USER 10001

ENTRYPOINT ["python", "-m", "flask", "run", "--host", "::"]
```

Docker Scout laat nu 0 kwetsbaarheden zien (het waren er 3 Critical, 21 High, 18 Medium en 48 Low) en 47 packages (het waren er 127).

![Docker Scout na de fix](images/docker-scout-na.png)

Ook is het image veel kleiner geworden. Gecomprimeerd ging het van 118,93 MB naar 17 MB (zoals Docker Hub het toont) en uitgepakt van ongeveer 437 MB naar 73 MB (lokaal gemeten).

