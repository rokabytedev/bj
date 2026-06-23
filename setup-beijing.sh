#!/usr/bin/env bash
# setup-beijing.sh — 在北京新机 WSL(Ubuntu) 内运行一次,把它配成住宅出口节点。
# 用法:  PREAUTH_KEY='hskey-auth-xxxx' bash setup-beijing.sh
# 自包含 + 自检 + 末尾打印【回报块】。只动本机 WSL,绝不触碰 VPS。
set -uo pipefail
HEADSCALE_URL="https://hs.the-third-mind.com"
NODE_HOSTNAME="beijing"
AUTHORIZED_KEYS='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIETSs/s9xDnGKiEz3NgcB0uFGIP0Ljsl5NdfBQS/bF5 hilo-tailnet
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDnYd8/9v2WfcYGe3pI1Uh/KLMFEgsumkA/3sR0/OFVA mac-tailnet
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBohvYpdh1R5FT/vh0dpIOgewrUeG+o+ZcOhSw30Y2PA iphone-tailnet'

say(){ echo -e "\n\033[1;36m[setup-beijing] $*\033[0m"; }
die(){ echo -e "\n\033[1;31m[setup-beijing][FATAL] $*\033[0m" >&2; exit 1; }

# 0. 前置
# PREAUTH_KEY 可选:给了就用它直接入网;没给则走"交互注册"(脚本会打印一行 nodekey 让你截图发回)。
[ "$(id -u)" -ne 0 ] || die "请用普通用户运行(脚本按需 sudo),勿直接 root。"
command -v sudo >/dev/null || die "没有 sudo。"
grep -qi microsoft /proc/version 2>/dev/null || say "提醒:似乎不在 WSL,继续。"

# 1. systemd 必须先就位(wsl.conf 改后需 wsl --shutdown 才生效)
sudo tee /etc/wsl.conf >/dev/null <<'WSLCONF'
[boot]
systemd=true
[network]
hostname=beijing
generateHosts=true
WSLCONF
if ! systemctl is-system-running 2>/dev/null | grep -qiE 'running|degraded'; then
  die "已写好 /etc/wsl.conf 开 systemd。请在 Windows PowerShell 跑 'wsl --shutdown',重开 Ubuntu 后【再次运行本脚本】(第二次自动续)。"
fi

# 2. 主机名
sudo hostnamectl set-hostname "$NODE_HOSTNAME" 2>/dev/null || true

# 3. IPv4 转发(出口必须)+持久化 + 真值校验
say "开启并持久化 IPv4 转发"
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale-exit.conf >/dev/null
sudo sysctl -p /etc/sysctl.d/99-tailscale-exit.conf || die "sysctl 应用失败"
[ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ] || die "ip_forward 未生效"

# 4. 装 tailscale
command -v tailscale >/dev/null || { say "装 tailscale"; curl -fsSL https://tailscale.com/install.sh | sh || die "tailscale 安装失败"; }
sudo systemctl enable --now tailscaled || die "tailscaled 起不来(确认 systemd 生效)"

# 5. sshd 仅公钥
say "装并加固 OpenSSH(仅公钥)"
sudo apt-get update -y || say "apt update 有警告(源超时?)继续"
sudo apt-get install -y openssh-server || die "装 openssh-server 失败"
install -d -m 700 "$HOME/.ssh"
printf '%s\n' "$AUTHORIZED_KEYS" > "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
sudo tee /etc/ssh/sshd_config.d/10-hardening.conf >/dev/null <<'SSHD'
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
PermitRootLogin no
SSHD
sudo sshd -t || die "sshd 配置语法错误"
sudo systemctl enable ssh 2>/dev/null || sudo systemctl enable sshd
sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd

# 6. 入网+宣告出口(幂等:已 Running 跳过 up,避免重复)
if tailscale status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; then
  say "tailscale 已 Running,跳过 up(幂等)"
elif [ -n "${PREAUTH_KEY:-}" ]; then
  say "用 PREAUTH_KEY 直接入网并宣告出口"
  sudo tailscale up --login-server="$HEADSCALE_URL" --advertise-exit-node \
    --ssh=false --accept-dns=false --hostname="$NODE_HOSTNAME" \
    --authkey="$PREAUTH_KEY" --reset || die "tailscale up 失败(key 过期? 能否连 VPS:443?)"
else
  say "===== 交互注册:不用你输入任何东西 ====="
  say "下面 tailscale 会打印一行带 nodekey 的地址(形如 .../register/nodekey:xxxx)。"
  say "★ 把那一行【截图】发给 Claude —— 它在服务器上注册后,本命令会自动继续,不要关窗口。"
  sudo tailscale up --login-server="$HEADSCALE_URL" --advertise-exit-node \
    --ssh=false --accept-dns=false --hostname="$NODE_HOSTNAME" --reset || die "tailscale up 失败(能否连 VPS:443?)"
fi
# 把"宣告出口"作为持久 pref 落地(无 --reset 副作用),保证跨重启稳定
sudo tailscale set --advertise-exit-node 2>/dev/null || true
sudo tailscale set --ssh=false 2>/dev/null || true

# 7. SNAT 自检(WSL2 NAT 下出口必须有 MASQUERADE/ts- 链,否则有去无回)
if sudo iptables -t nat -S 2>/dev/null | grep -qiE 'MASQUERADE|ts-'; then NAT=yes; else NAT='NO(出口可能有去无回!)'; fi

# 8. 自检 + 回报(关键项真值断言)
ip4="$(tailscale ip -4 2>/dev/null | head -1)"
fwd="$(cat /proc/sys/net/ipv4/ip_forward)"; FWD_V=$([ "$fwd" = 1 ] && echo OK || echo '*** FATAL ***')
pw="$(sudo sshd -T 2>/dev/null | awk 'tolower($1)=="passwordauthentication"{print $2}')"; PW_V=$([ "$pw" = no ] && echo OK || echo '*** FATAL ***')
runssh="$(tailscale debug prefs 2>/dev/null | grep -o '"RunSSH"[^,]*' | head -1)"
backend="$(tailscale status --json 2>/dev/null | grep -o '"BackendState"[^,]*' | head -1)"
say "===== 把下面整段【回报块】复制贴回给 Claude ====="
echo "BEGIN-BEIJING-REPORT"
echo "user=$(whoami)         # 各客户端 ssh beijing 必须用这个用户名"
echo "host=$(hostname)"
echo "backend=$backend       # 期望含 Running"
echo "ts_ip4=$ip4"
echo "runssh=$runssh         # 期望 false"
echo "ip_forward_v4=$fwd $FWD_V"
echo "snat=$NAT"
echo "sshd_passwordauth=$pw $PW_V"
echo "authkeys_count=$(grep -c . "$HOME/.ssh/authorized_keys") # 期望 3"
echo "--- host key 指纹(钉死用) ---"
for t in ed25519 ecdsa rsa; do f="/etc/ssh/ssh_host_${t}_key.pub"; [ -f "$f" ] && echo "$t: $(ssh-keygen -lf "$f" 2>/dev/null)"; done
echo "--- ed25519 known_hosts 行(按名 beijing 钉) ---"
f="/etc/ssh/ssh_host_ed25519_key.pub"; [ -f "$f" ] && echo "beijing $(awk '{print $1" "$2}' "$f")"
echo "--- status ---"; tailscale status 2>/dev/null | head -8
echo "END-BEIJING-REPORT"
say "完成。出口路由待 Claude 在 VPS approve(安全),并当场实测手机能否选 beijing 出口。"
