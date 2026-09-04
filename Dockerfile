# Use an official Python runtime as a parent image
FROM python:3.14-slim-bookworm

# Set work directory in the container
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends pipx \
    && rm -rf /var/lib/apt/lists/*

# Install poetry
RUN /usr/bin/pipx install poetry

# Copy only requirements to cache them in docker layer
COPY /content/pyproject.toml /content/poetry.lock /app/

# Project initialization
RUN /root/.local/bin/poetry install --no-interaction --no-ansi --no-root

# Copying the project files into the container
COPY /content/. /app/

# Expose webserver port
# EXPOSE 5000

# Run the webserver
CMD ["/root/.local/bin/poetry", "run", "flask", "run", "-h", "0.0.0.0"]
