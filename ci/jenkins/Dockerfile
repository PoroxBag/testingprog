FROM jenkins/jenkins:lts-jdk17

USER root

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Инструменты для Lab7 прямо на built-in node (учёбный стенд)
RUN apt-get update && apt-get install -y --no-install-recommends \
      docker.io curl ca-certificates git bash procps \
      python3 python3-pip python3-venv \
      chromium chromium-driver ipmitool \
      libpixman-1-0 libfdt1 libslirp0 libglib2.0-0 zlib1g \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/chromium /usr/bin/google-chrome || true \
    && ln -sf /usr/bin/chromedriver /usr/local/bin/chromedriver || true

# Python-зависимости для тестов (дополнительно venv в workspace)
COPY requirements-ci.txt /tmp/requirements-ci.txt
RUN pip3 install --break-system-packages --no-cache-dir -r /tmp/requirements-ci.txt \
 || pip3 install --no-cache-dir -r /tmp/requirements-ci.txt

USER jenkins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    CASC_JENKINS_CONFIG="/var/jenkins_home/casc.yaml"
