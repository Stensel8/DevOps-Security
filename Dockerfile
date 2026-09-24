# Bouwen: hier staan Poetry en pip. Dit blijft in de builder en komt niet in het eindimage.
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

# Draaien: geen Poetry, geen pip, geen build-tools en niet als root
FROM python:3.14-alpine@sha256:9e9fde4d32eedce0b661d9ab91e826b62dddf28e928c230ec55f1866cac66b01

ENV PATH="/app/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# De enige stap als root: pip weghalen, want die staat in een map van root. Verder draait alles als 10001.
RUN PIP_ROOT_USER_ACTION=ignore pip uninstall -y pip

# De app-map moet van de gebruiker zijn: SQLite en het logbestand schrijven hier
COPY --chown=10001:10001 content/ /app/
COPY --from=builder --chown=10001:10001 /app/venv /app/venv

WORKDIR /app
USER 10001:10001

ENTRYPOINT ["python", "-m", "flask", "run", "--host", "::"]
