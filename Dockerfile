# Dit Dockerfile bouwt in twee stappen (multi-stage). Er zijn dus twee images:
#
#   1. builder  Het tussenimage waarmee gebouwd wordt. Hierin staan Poetry en pip en hier worden de
#               dependencies uit poetry.lock geïnstalleerd. Dit image wordt niet gepusht.
#   2. runtime  Het uiteindelijke applicatie-image, dat naar Docker Hub gaat (stensel8/devops-security).
#               Hierin zit alleen de app en de venv met dependencies uit de builder. Geen Poetry, geen pip
#               en het draait niet als root.

# ---------- Stap 1 van 2: builder (tussenimage, wordt niet gepusht) ----------
# De builder draait als gewone gebruiker (10001), root is hier alleen nodig om die gebruiker aan te maken.
FROM python:3.14-alpine@sha256:9e9fde4d32eedce0b661d9ab91e826b62dddf28e928c230ec55f1866cac66b01 AS builder

RUN adduser -D -u 10001 builder && mkdir /app && chown builder /app
USER 10001
WORKDIR /app

# Poetry in een eigen venv, zodat het niet mee gaat naar het eindimage
RUN python -m venv /home/builder/poetry && /home/builder/poetry/bin/pip install --no-cache-dir poetry==2.5.1

# Alleen de dependencies uit poetry.lock, in de venv van de app (zonder pip)
RUN python -m venv --without-pip /app/venv
COPY --chown=10001:10001 content/pyproject.toml content/poetry.lock ./
RUN VIRTUAL_ENV=/app/venv /home/builder/poetry/bin/poetry install --no-root --only main --no-interaction --no-ansi

# ---------- Stap 2 van 2: runtime (het applicatie-image dat wordt gepusht) ----------
# Begint opnieuw vanaf de schone basisimage. Uit de builder nemen we straks alleen /app/venv over.
FROM python:3.14-alpine@sha256:9e9fde4d32eedce0b661d9ab91e826b62dddf28e928c230ec55f1866cac66b01 AS runtime

ENV PATH="/app/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# De enige stap als root: pip weghalen, want die staat in een map van root. Verder draait alles als 10001.
RUN PIP_ROOT_USER_ACTION=ignore pip uninstall -y pip

# De app-map moet van de gebruiker zijn: SQLite en het logbestand schrijven hier
COPY --chown=10001:10001 content/ /app/
# Alleen de venv met de dependencies komt uit de builder. De rest van de builder (Poetry, pip) blijft daar.
COPY --from=builder --chown=10001:10001 /app/venv /app/venv

WORKDIR /app
USER 10001:10001

ENTRYPOINT ["python", "-m", "flask", "run", "--host", "::"]
