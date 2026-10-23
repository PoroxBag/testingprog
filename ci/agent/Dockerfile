# CI-агент для OpenBMC Lab7: Python-тесты, Locust, Chrome (WebUI), curl.
# Бинарь qemu-system-arm и MTD-образ монтируются из workspace.
FROM python:3.12-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates bash procps \
      chromium chromium-driver \
      fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

# Selenium ожидает "google-chrome" / chromedriver в PATH
RUN ln -sf /usr/bin/chromium /usr/bin/google-chrome \
 && ln -sf /usr/bin/chromedriver /usr/local/bin/chromedriver || true

WORKDIR /workspace
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt selenium

CMD ["bash"]
