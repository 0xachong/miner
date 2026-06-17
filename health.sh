#!/bin/sh
# 健康检查响应:推理平台(如 EdgeOne Infer)探这个端口时恒回 200 OK。
# 由 entrypoint.sh 里的 socat 对每个连接调用一次(SYSTEM:/opt/miner/health.sh)。
printf 'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 3\r\nConnection: close\r\n\r\nok\n'
