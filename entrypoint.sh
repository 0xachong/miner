#!/usr/bin/env bash
set -euo pipefail
WALLET="${WALLET:?必须设置 WALLET(你的 prl1 收款地址)}"
POOL="${POOL:-stratum+tcp://us2.alphapool.tech:5566}"
WORKER="${WORKER:-$(hostname)}"
DEVICES="${DEVICES:-all}"
POWER_LIMIT_PCT="${POWER_LIMIT_PCT:-}"
STATUS_INTERVAL="${STATUS_INTERVAL:-30}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
RELAY_HOST="${RELAY_HOST:-}"
RELAY_PORT="${RELAY_PORT:-22}"
RELAY_LOCAL_PORT="${RELAY_LOCAL_PORT:-15566}"
POOL_UPSTREAM="${POOL_UPSTREAM:-}"
RELAY_KEY_PATH="${RELAY_KEY_PATH:-/run/secrets/relay_key}"
RELAY_KEY_B64="${RELAY_KEY_B64:-}"
KEYFILE=""

start_relay() {
  : "${POOL_UPSTREAM:?设了 RELAY_HOST 就必须设 POOL_UPSTREAM}"
  KEYFILE="$RELAY_KEY_PATH"
  if [[ -n "$RELAY_KEY_B64" ]]; then KEYFILE=/tmp/relay_key; echo "$RELAY_KEY_B64" | base64 -d > "$KEYFILE"; fi
  [[ -f "$KEYFILE" ]] || { echo "[err] 缺少中转私钥:$KEYFILE"; exit 1; }
  chmod 600 "$KEYFILE" 2>/dev/null || true
  echo "[pearl-miner] 经中转 $RELAY_HOST 建隧道 127.0.0.1:$RELAY_LOCAL_PORT -> $POOL_UPSTREAM"
  AUTOSSH_GATETIME=0 autossh -M 0 -f -N -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o BatchMode=yes \
    -i "$KEYFILE" -p "$RELAY_PORT" -L "$RELAY_LOCAL_PORT:$POOL_UPSTREAM" "$RELAY_HOST"
  for _ in $(seq 1 20); do
    (exec 3<>"/dev/tcp/127.0.0.1/$RELAY_LOCAL_PORT") 2>/dev/null && { exec 3>&-; break; }; sleep 1
  done
  POOL="stratum+tcp://127.0.0.1:$RELAY_LOCAL_PORT"
  echo "[pearl-miner] 隧道就绪,矿机将连 $POOL"
}

[[ -n "$RELAY_HOST" ]] && start_relay
echo "[pearl-miner] wallet=${WALLET:0:10}...${WALLET: -6} pool=$POOL worker=$WORKER devices=$DEVICES"

if [[ -n "$POWER_LIMIT_PCT" ]]; then
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "[pearl-miner] 设功耗墙到默认TDP的 ${POWER_LIMIT_PCT}%"
    nvidia-smi -pm 1 >/dev/null 2>&1 || echo "[warn] 持久模式失败"
    nvidia-smi --query-gpu=index,power.default_limit --format=csv,noheader,nounits 2>/dev/null \
      | while IFS=, read -r idx defw; do
          defw=$(echo "$defw" | tr -d ' ' | cut -d. -f1); [[ -z "$defw" ]] && continue
          lim=$(( defw * POWER_LIMIT_PCT / 100 ))
          nvidia-smi -i "$idx" -pl "$lim" >/dev/null 2>&1 && echo "[pearl-miner] GPU$idx -> ${lim}W" || echo "[warn] GPU$idx 功耗墙需 --cap-add SYS_ADMIN"
        done
  else echo "[warn] 无 nvidia-smi,跳过功耗墙"; fi
fi

# dashboard 上报 agent(复用中转私钥)
if [[ "${REPORT:-off}" == "on" && -n "$RELAY_HOST" ]]; then
  mkdir -p /var/log
  export AGENT_RELAY="$RELAY_HOST" AGENT_KEY="${KEYFILE:-$RELAY_KEY_PATH}" \
    AGENT_HOST="${HOST_ID:-$WORKER}" AGENT_TOKEN="${DASHBOARD_TOKEN:-prl-x7k2m9vq}" \
    AGENT_LOG=/var/log/miner.log AGENT_TUNNEL_PORT="$RELAY_LOCAL_PORT"
  echo "[pearl-miner] dashboard 上报已开启 -> $RELAY_HOST (HOST_ID=${HOST_ID:-$WORKER})"
  python3 /opt/miner/agent.py &
fi

# 启动矿机
if [[ "${REPORT:-off}" == "on" ]]; then
  mkdir -p /var/log
  /opt/miner/alpha-miner --pool "$POOL" --address "$WALLET" --worker "$WORKER" \
    --devices "$DEVICES" --status-interval "$STATUS_INTERVAL" $EXTRA_ARGS 2>&1 | tee /var/log/miner.log
else
  exec /opt/miner/alpha-miner --pool "$POOL" --address "$WALLET" --worker "$WORKER" \
    --devices "$DEVICES" --status-interval "$STATUS_INTERVAL" $EXTRA_ARGS
fi
