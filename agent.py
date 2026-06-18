#!/usr/bin/env python3
"""容器内 dashboard 上报 agent:采 GPU/算力/隧道/系统,经中转 SSH 推到 dashboard。
全部走环境变量,复用中转隧道的私钥。"""
import json, os, re, shutil, socket, subprocess, time

HK = os.environ.get("AGENT_RELAY", "")              # ssh 目标=中转机(同 RELAY_HOST)
KEY = os.environ.get("AGENT_KEY", "/tmp/relay_key") # 复用中转私钥
HOST_ID = os.environ.get("AGENT_HOST") or socket.gethostname()
TOKEN = os.environ.get("AGENT_TOKEN", "prl-x7k2m9vq")
LOG = os.environ.get("AGENT_LOG", "/var/log/miner.log")
TPORT = int(os.environ.get("AGENT_TUNNEL_PORT", "11200"))
INTERVAL = 30


def sh(cmd, t=10):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=t).stdout.strip()
    except Exception:
        return ""


def fnum(s):
    try:
        return float(s)
    except Exception:
        return None


def gpu_stats():
    out = sh("nvidia-smi --query-gpu=index,name,utilization.gpu,power.draw,temperature.gpu,"
             "memory.used,memory.total,fan.speed,power.limit,power.default_limit "
             "--format=csv,noheader,nounits")
    g = []
    for ln in out.splitlines():
        p = [x.strip() for x in ln.split(",")]
        if len(p) < 7:
            continue
        g.append({"idx": int(p[0]), "name": p[1], "util": fnum(p[2]), "power": fnum(p[3]),
                  "temp": fnum(p[4]), "mem_used": fnum(p[5]), "mem_total": fnum(p[6]),
                  "fan": fnum(p[7]) if len(p) > 7 else None,
                  "plim": fnum(p[8]) if len(p) > 8 else None,
                  "pdef": fnum(p[9]) if len(p) > 9 else None})
    return g


def miner_stats(ngpu):
    hr = {}
    try:
        with open(LOG, "rb") as f:
            f.seek(max(0, os.fstat(f.fileno()).st_size - 65536))
            txt = f.read().decode(errors="ignore")
        # lpminer 格式: "GPU #0   123.4 TH/s"
        for m in re.finditer(r"GPU #(\d+)\s.*?([0-9.]+)\s*(PH|TH|GH)/s", txt):
            v, u = float(m.group(2)), m.group(3)
            v = v * 1000 if u == "PH" else (v / 1000 if u == "GH" else v)
            hr[int(m.group(1))] = round(v, 1)
        # alpha-miner 格式回退: "hashrate_th_s=123.4"(无每卡序号,记到 gpu0)
        if not hr:
            ms = re.findall(r"hashrate_th_s=([0-9.]+)", txt)
            if ms:
                hr[0] = float(ms[-1])
    except Exception:
        pass
    alive = bool(hr)
    return {str(g): {"alive": alive and g in hr, "hashrate_th": hr.get(g, 0.0)} for g in range(ngpu)}


def tunnel_ok():
    try:
        s = socket.create_connection(("127.0.0.1", TPORT), timeout=5)
        s.close()
        return True
    except OSError:
        return False


def sys_stats():
    mem = {}
    with open("/proc/meminfo") as f:
        for ln in f:
            k, v = ln.split(":", 1)
            mem[k] = int(v.split()[0])
    with open("/proc/uptime") as f:
        up = int(float(f.read().split()[0]))
    du = shutil.disk_usage("/")
    return {"load1": round(os.getloadavg()[0], 2),
            "mem_used_mb": (mem["MemTotal"] - mem["MemAvailable"]) // 1024,
            "mem_total_mb": mem["MemTotal"] // 1024,
            "disk_used_pct": round(du.used / du.total * 100, 1), "uptime_s": up}


def main():
    if not HK:
        print("[agent] 未设 AGENT_RELAY,上报关闭")
        return
    ngpu = len(gpu_stats()) or 1
    while True:
        t0 = time.time()
        try:
            rep = {"host": HOST_ID, "role": "miner", "ts": int(time.time()),
                   "gpus": gpu_stats(), "miners": miner_stats(ngpu),
                   "tunnel_ok": tunnel_ok(), "sys": sys_stats(), "pool": "herominers"}
            subprocess.run(
                ["ssh", "-i", KEY, "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
                 "-o", "StrictHostKeyChecking=accept-new", HK,
                 f"curl -s -m 8 -X POST -H 'X-Token: {TOKEN}' --data-binary @- "
                 "http://127.0.0.1:8080/api/report"],
                input=json.dumps(rep), text=True, capture_output=True, timeout=25)
        except Exception:
            pass
        time.sleep(max(5, INTERVAL - (time.time() - t0)))


if __name__ == "__main__":
    main()
