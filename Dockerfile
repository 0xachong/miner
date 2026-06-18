# Pearl (PRL) GPU miner — 通用 Docker 镜像(含可选中转隧道 + dashboard 上报)
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

LABEL org.opencontainers.image.title="pearl-miner"
LABEL org.opencontainers.image.source="https://github.com/0xachong/miner"

ARG ALPHA_MINER_VERSION=v1.6.0
ARG ALPHA_MINER_SHA256=b6f7fd43f125db9b67ceeb7c7b98be43f645700854389b922736bd643f7d0009

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl tini openssh-client autossh python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/miner

RUN curl -fsSL -o alpha-miner \
      "https://github.com/AlphaMine-Tech/alpha-miner/releases/download/${ALPHA_MINER_VERSION}/alpha-miner" \
    && echo "${ALPHA_MINER_SHA256}  alpha-miner" | sha256sum -c - \
    && chmod +x alpha-miner

COPY entrypoint.sh /opt/miner/entrypoint.sh
COPY agent.py /opt/miner/agent.py
RUN chmod +x /opt/miner/entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/miner/entrypoint.sh"]
