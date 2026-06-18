# Pearl (PRL) GPU miner — 通用 Docker 镜像
# 矿机二进制在 build 时从官方 GitHub Release 下载 + sha256 校验(不把二进制塞进仓库)
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

LABEL org.opencontainers.image.title="pearl-miner"
LABEL org.opencontainers.image.description="Generic Dockerized Pearl (PRL) GPU miner with optional SSH-relay tunnel + dashboard reporting"
LABEL org.opencontainers.image.source="https://github.com/0xachong/miner"

ARG ALPHA_MINER_VERSION=v1.6.0
ARG ALPHA_MINER_SHA256=b6f7fd43f125db9b67ceeb7c7b98be43f645700854389b922736bd643f7d0009
# GitHub 下载代理前缀,国内加速用;留空则直连 GitHub
ARG GH_PROXY=https://gh-proxy.com/

# apt 换国内源加速(阿里云),失败则保持原源不影响构建
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g; s@//.*security.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl tini openssh-client autossh socat python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/miner

RUN curl -fsSL -o alpha-miner \
      "${GH_PROXY}https://github.com/AlphaMine-Tech/alpha-miner/releases/download/${ALPHA_MINER_VERSION}/alpha-miner" \
    && echo "${ALPHA_MINER_SHA256}  alpha-miner" | sha256sum -c - \
    && chmod +x alpha-miner

COPY entrypoint.sh health.sh agent.py /opt/miner/
RUN chmod +x /opt/miner/entrypoint.sh /opt/miner/health.sh

# 推理平台(如 EdgeOne Infer)会对该端口做就绪/健康探针;矿机本身不监听端口,
# 故内置一个轻量 HTTP 健康端,平台要求的端口请用 PORT 覆盖并在控制台对齐。
ENV PORT=8080
EXPOSE 8080

# 默认收款地址(可在运行时用环境变量 WALLET 覆盖)。仅为收款地址,非私钥。
ENV WALLET=prl1pf0945gyhvlzqvjwkqxy0l3x9wf783d2m7sjvrfm6s2f2l8xjuuys84z7df

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/miner/entrypoint.sh"]
