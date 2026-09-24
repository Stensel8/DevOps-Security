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
