# Dit Dockerfile bouwt in twee stappen (multi-stage), dus er zijn twee images:
#   1. builder  Tussenimage waarmee gebouwd wordt: uv installeert hier de dependencies. Wordt niet gepusht.
#   2. runtime  Het applicatie-image dat naar Docker Hub gaat: alleen de app en de dependencies.
#               Geen uv, geen pip en het draait niet als root.
#
# COPY <van> <naar>: de bestemming is altijd in het image dat op dat moment gebouwd wordt. Zonder --from
# is de bron jouw repo, met --from=builder is de bron de builder-stage.

# ---------- Stap 1 van 2: builder (tussenimage, wordt niet gepusht) ----------
FROM python:3.15-alpine@sha256:20a82dbc2783112ddb91d1534603f802d222a3e63e593cd002eb2ac534e70211 AS builder

# uv zelf komt niet van pip of apt, maar als los, gepinned binary uit het officiële uv-image.
COPY --from=ghcr.io/astral-sh/uv@sha256:32a7bb39b496babbd997b0a39a4d66c126bdaf5661b302bf6f06abda8deca6ff /uv /usr/local/bin/uv

WORKDIR /app
# UV_PYTHON_DOWNLOADS=never: gebruik de Python die al in dit image zit (van de base image hierboven),
# niet er zelf eentje downloaden. UV_PROJECT_ENVIRONMENT zet de venv op hetzelfde pad als voorheen.
ENV UV_PROJECT_ENVIRONMENT=/app/.venv UV_PYTHON_DOWNLOADS=never UV_LINK_MODE=copy

# Uit jouw repo, naar /app in de builder: alleen de lijst met dependencies, niet de code.
# Zolang die twee bestanden gelijk blijven, hergebruikt Docker de installatie uit de cache.
COPY app/pyproject.toml app/uv.lock ./

# --locked faalt hard als uv.lock niet meer bij pyproject.toml past (zelfde als poetry check --lock deed).
# --no-install-project: dit is geen package om te installeren, alleen de dependencies eruit.
RUN uv sync --locked --no-install-project

# ---------- Stap 2 van 2: runtime (het applicatie-image dat wordt gepusht) ----------
FROM python:3.15-alpine@sha256:20a82dbc2783112ddb91d1534603f802d222a3e63e593cd002eb2ac534e70211 AS runtime

# Pip weghalen: de app heeft het niet nodig en scanners klagen over oude onderdelen erin
RUN PIP_ROOT_USER_ACTION=ignore pip uninstall -y pip

ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

# Uit jouw repo, naar /app in dit image: de app zelf (app/). Van gebruiker 10001, want SQLite en het
# logbestand schrijven in de app-map.
COPY --chown=10001:10001 app/ /app/
# Uit de builder (--from=builder), naar dit image: de venv met de dependencies. Het enige dat we uit de
# builder meenemen. uv en pip blijven daar.
COPY --from=builder --chown=10001:10001 /app/.venv /app/.venv

WORKDIR /app
USER 10001:10001

# Gunicorn is een echte webserver voor productie. Flask's eigen server (flask run) is alleen voor ontwikkelen.
# Sinds week 3, tijdens commit 830426d.
# --worker-tmp-dir: gunicorn heeft een schrijfbare map voor zijn werkbestanden nodig. Het bestandssysteem is
# read-only, dus we gebruiken /dev/shm (werkgeheugen), dat is altijd schrijfbaar. De control-socket van gunicorn
# (voor beheer op afstand) hebben we niet nodig en zou ook naar het read-only bestandssysteem schrijven.
ENTRYPOINT ["gunicorn", "--bind", "[::]:5000", "--worker-tmp-dir", "/dev/shm", "--no-control-socket", "app:app"]
