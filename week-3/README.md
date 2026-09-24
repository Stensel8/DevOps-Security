# Week 3

## 3.2 Docker Scout

Het image in de beginstaat is kwetsbaar. Docker Scout laat 96 kwetsbaarheden zien, waarvan 3 Critical en 21 High. Het meeste zit in de basisimage (`python:3-slim-bookworm`: 3 Critical, 15 High). Mijn eigen lagen hebben ook 9 High, door `apt-get install pipx`.

<img src="images/github-actions-build.png" alt="Build van het image in de beginstaat" width="720">

<img src="images/docker-scout.png" alt="Docker Scout op Docker Hub" width="720">

<img src="images/docker-scout-voor.png" alt="Docker Scout voor de fix" width="720">

### Alle kwetsbaarheden fixen

Ik heb de Dockerfile aangepast (commit [`790a9b8`](https://github.com/Stensel8/DevOps-Security/commit/790a9b8)):

- `python:3.14-alpine` als basis in plaats van Debian.
- Het image draait als gebruiker 10001, niet als root.
- Twee stappen (multi-stage): een **builder** waarin Poetry de dependencies installeert en een **runtime** met alleen de app en de venv. Alleen de runtime gaat naar Docker Hub (`target: runtime`). Poetry en pip zitten dus niet in het image dat draait.

```mermaid
flowchart LR
    A["python:3.14-alpine"] --> B["<b>builder</b> (tussenimage)<br/>Poetry + pip<br/>installeert de dependencies<br/>203 MB, wordt niet gepusht"]
    A --> C["<b>runtime</b> (applicatie-image)<br/>de app + de venv<br/>geen Poetry, geen pip, niet als root<br/>84,5 MB"]
    B -- "alleen de venv (/app/.venv)" --> C
    C --> D[("Docker Hub<br/>stensel8/devops-security")]
```

De twee `FROM`-regels in de [Dockerfile](../Dockerfile) zijn bewust: elke `FROM` begint een nieuw, schoon image. `COPY --from=builder` haalt alleen `/app/.venv` uit de builder. Pip haal ik uit de runtime, want de app heeft het niet nodig en scanners melden de gebundelde onderdelen (msgpack, setuptools). De builder draait als root, maar die stage komt niet in het image dat draait.

```dockerfile
FROM python:3.14-alpine@sha256:9e9f... AS builder
COPY app/pyproject.toml app/poetry.lock ./
RUN poetry install --no-root --only main --no-interaction --no-ansi

FROM python:3.14-alpine@sha256:9e9f... AS runtime
RUN PIP_ROOT_USER_ACTION=ignore pip uninstall -y pip
COPY --chown=10001:10001 app/ /app/
COPY --from=builder --chown=10001:10001 /app/.venv /app/.venv
USER 10001:10001
```

Ik heb Alpine gekozen. Trivy telt op de Debian-basisimage 252 kwetsbaarheden en op Alpine 3 (die komen uit pip en verdwijnen in de runtime). Trivy telt anders dan Docker Scout, want scanners gebruiken andere databases.

```
$ trivy image --scanners vuln python:3.14-slim-bookworm
Total: 252 (UNKNOWN: 2, LOW: 86, MEDIUM: 104, HIGH: 55, CRITICAL: 5)

$ trivy image --scanners vuln python:3.14-alpine
Total: 3 (UNKNOWN: 0, LOW: 0, MEDIUM: 1, HIGH: 2, CRITICAL: 0)      # uit pip
```

Trivy op mijn twee stages, lokaal gebouwd met `docker build --target builder` en `--target runtime` (getagd als `proof-builder` en `proof-runtime`):

```
$ docker images --format '{{.Repository}} {{.Size}}' | grep proof
proof-runtime 84.5MB
proof-builder 203MB

$ trivy image --severity HIGH,CRITICAL --scanners vuln proof-builder
Python (python-pkg)
Total: 2 (HIGH: 2, CRITICAL: 0)
│ msgpack    │ GHSA-6v7p-g79w-8964 │ HIGH │ fixed │ 1.1.2  │ 1.2.1  │
│ setuptools │ CVE-2025-47273      │ HIGH │ fixed │ 70.3.0 │ 78.1.1 │

$ trivy image --severity HIGH,CRITICAL --scanners vuln proof-runtime
proof-runtime (alpine 3.24.2)   alpine       0
blinker, click, flask, gunicorn, itsdangerous, jinja2, markupsafe, werkzeug   python-pkg   0
```

Docker Scout laat na de fix 0 kwetsbaarheden zien (het waren er 3 Critical, 21 High, 18 Medium en 48 Low) en 47 packages (het waren er 127).

<img src="images/docker-scout-na.png" alt="Docker Scout na de fix" width="720">

Het image is ook kleiner. Gecomprimeerd ging het van 118,93 MB naar 17 MB (zoals Docker Hub het toont), uitgepakt van ongeveer 437 MB naar 84,5 MB (lokaal gemeten, met gunicorn erbij).

### Extra in de app

Buiten de opdracht heb ik nog drie kleine dingen aangepast. De app draait onder gunicorn in plaats van `flask run`, want dat is de ontwikkelserver ([`830426d`](https://github.com/Stensel8/DevOps-Security/commit/830426d)). Vanwege het read-only bestandssysteem staat er `--worker-tmp-dir /dev/shm` en `--no-control-socket` bij. De pagina's staan in Jinja-templates die vanzelf escapen ([`071ad02`](https://github.com/Stensel8/DevOps-Security/commit/071ad02)). Elk antwoord krijgt `X-Content-Type-Options`, `X-Frame-Options` en `Referrer-Policy` ([`8e01026`](https://github.com/Stensel8/DevOps-Security/commit/8e01026)). Daarna heb ik het advies van [securityheaders.com](https://securityheaders.com) opgevolgd, dat gaf een D. Er zijn `Content-Security-Policy`, `Permissions-Policy`, `Cross-Origin-Opener-Policy` en `Cross-Origin-Resource-Policy` bijgekomen. De CSP staat alleen scripts, CSS en plaatjes van de app zelf toe. De achtergrondplaatjes kwamen van `cdn.glitch.com`, maar dat domein bestaat niet meer, dus die heb ik niet toegestaan.

De screenshot van Docker Scout hierboven is van vóór gunicorn. Trivy geeft op het huidige image 0 kwetsbaarheden.
