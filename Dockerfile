FROM pytorch/pytorch:2.6.0-cuda12.4-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

# System deps
RUN apt-get update -y && apt-get install -y --no-install-recommends \
      git curl wget ca-certificates \
      nginx apache2-utils \
      rclone \
      psmisc lsof tini \
    && rm -rf /var/lib/apt/lists/*

# OhMyRunPod + civitai-downloader (pip)
RUN python -m pip install -U pip setuptools wheel \
 && python -m pip install -U OhMyRunPod civitai-downloader

# code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# runpodctl (best-effort: script officiel)
# (si le script change/échoue, on le fera au runtime, mais en général ça passe)
RUN curl -fsSL https://docs.runpod.io/runpodctl/install.sh | bash || true

# Startup
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 7860 8080

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/start.sh"]
