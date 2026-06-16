# pearl-miner — 通用 Pearl (PRL) GPU 挖矿 Docker 镜像

把 Pearl GPU 挖矿打包成开箱即用的 Docker 镜像:一条 `docker run` 就能在任意带 NVIDIA GPU 的机器上挖矿,所有配置走环境变量,内置可选的中转 SSH 隧道(大陆机器经海外中转连矿池)。

> 矿机 `alpha-miner` 为第三方闭源二进制、自带 1% 抽水。本镜像在 build 时从官方 GitHub Release 下载并校验 sha256,不重新分发二进制。仓库内不含任何钱包种子/私钥/中转密钥。

## 前置要求
- NVIDIA GPU + 驱动(CUDA 12.x 兼容)
- Docker + NVIDIA Container Toolkit

## 海外机器:直连矿池
```bash
docker run -d --name pearl-miner --restart unless-stopped --gpus all \
  -e WALLET=prl1你的收款地址 -e WORKER=rig-01 \
  ghcr.io/0xachong/miner:latest
```

## 大陆机器:经中转 SSH 隧道
```bash
docker run -d --name pearl-miner --restart unless-stopped --gpus all \
  -e WALLET=prl1你的收款地址 -e WORKER=rig-01 \
  -e RELAY_HOST=ubuntu@你的中转机IP \
  -e POOL_UPSTREAM=us2.alphapool.tech:5566 \
  -v /path/to/relay_key:/run/secrets/relay_key:ro \
  ghcr.io/0xachong/miner:latest
```
中转机要求:海外 Linux、能连矿池、已把该私钥的公钥加进 `~/.ssh/authorized_keys`。

## docker compose
```bash
cp .env.example .env   # 填 WALLET(及可选 RELAY_*)
docker compose up -d && docker compose logs -f
```

## 环境变量
| 变量 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `WALLET` | 是 | — | 你的 `prl1` 收款地址 |
| `POOL` | | alphapool us2 | 直连时矿机连这个(用隧道则忽略) |
| `WORKER` | | 主机名 | worker 名 |
| `DEVICES` | | `all` | GPU:`all` 或 `0,1,2` |
| `POWER_LIMIT_PCT` | | 空 | 功耗墙=默认TDP×百分比(如 `90`),需 `--cap-add SYS_ADMIN` |
| `RELAY_HOST` | | 空 | 中转机 ssh 目标,如 `ubuntu@1.2.3.4`;空=直连 |
| `POOL_UPSTREAM` | 用隧道时 | alphapool us2 | 隧道转发到的真实矿池 host:port |
| `RELAY_LOCAL_PORT` | | `15566` | 容器内本地转发端口 |
| `RELAY_KEY_PATH` | | `/run/secrets/relay_key` | 挂载的 SSH 私钥路径 |
| `RELAY_KEY_B64` | | 空 | 或 base64 私钥(免挂载) |

## 镜像构建
push 到 `main` 后 GitHub Actions 自动 build 并发布到 `ghcr.io/0xachong/miner:latest`。
本地:`docker build -t pearl-miner .`

## 许可
仓库(Dockerfile/脚本)MIT。`alpha-miner` 二进制版权归其作者(含抽水),使用即接受其条款。
