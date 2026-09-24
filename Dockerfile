# Dit Dockerfile bouwt in twee stappen (multi-stage), dus er zijn twee images:
#   1. builder  Tussenimage waarmee gebouwd wordt: Poetry installeert hier de dependencies. Wordt niet gepusht.
#   2. runtime  Het applicatie-image dat naar Docker Hub gaat: alleen de app en de dependencies.
#               Geen Poetry, geen pip en het draait niet als root.
#
# COPY <van> <naar>: de bestemming is altijd in het image dat op dat moment gebouwd wordt. Zonder --from
# is de bron jouw repo, met --from=builder is de bron de builder-stage.

# ---------- Stap 1 van 2: builder (tussenimage, wordt niet gepusht) ----------
FROM python:3.14-alpine@sha256:9e9fde4d32eedce0b661d9ab91e826b62dddf28e928c230ec55f1866cac66b01 AS builder

WORKDIR /app
RUN pip install --no-cache-dir poetry==2.5.1

# Uit jouw repo, naar /app in de builder: alleen de lijst met dependencies, niet de code.
# Zolang die twee bestanden gelijk blijven, hergebruikt Docker de installatie uit de cache.
COPY content/pyproject.toml content/poetry.lock ./

# Poetry maakt de venv in /app/.venv (zonder pip) en installeert alleen de dependencies uit poetry.lock
RUN poetry config virtualenvs.in-project true \
    && poetry config virtualenvs.options.no-pip true \
    && poetry install --no-root --only main --no-interaction --no-ansi

# ---------- Stap 2 van 2: runtime (het applicatie-image dat wordt gepusht) ----------
FROM python:3.14-alpine@sha256:9e9fde4d32eedce0b661d9ab91e826b62dddf28e928c230ec55f1866cac66b01 AS runtime

# Pip weghalen: de app heeft het niet nodig en scanners klagen over oude onderdelen erin
RUN PIP_ROOT_USER_ACTION=ignore pip uninstall -y pip

ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

# Uit jouw repo, naar /app in dit image: de app zelf (content/). Van gebruiker 10001, want SQLite en het
# logbestand schrijven in de app-map.
COPY --chown=10001:10001 content/ /app/
# Uit de builder (--from=builder), naar dit image: de venv met de dependencies. Het enige dat we uit de
# builder meenemen. Poetry en pip blijven daar.
COPY --from=builder --chown=10001:10001 /app/.venv /app/.venv

WORKDIR /app
USER 10001:10001

# Gunicorn is een echte webserver voor productie. Flask's eigen server (flask run) is alleen voor ontwikkelen.
# --worker-tmp-dir: gunicorn heeft een schrijfbare map voor zijn werkbestanden nodig. Het bestandssysteem is
# read-only, dus we gebruiken /dev/shm (werkgeheugen), dat is altijd schrijfbaar. De control-socket van gunicorn
# (voor beheer op afstand) hebben we niet nodig en zou ook naar het read-only bestandssysteem schrijven.
ENTRYPOINT ["gunicorn", "--bind", "[::]:5000", "--worker-tmp-dir", "/dev/shm", "--no-control-socket", "app:app"]
