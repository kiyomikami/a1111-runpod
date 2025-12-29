#!/usr/bin/env bash
set -euo pipefail

WS="/workspace"
REPO="$WS/stable-diffusion-webui"
VENV="$WS/venv"
LOGDIR="$WS/logs"
mkdir -p "$LOGDIR"

# Kill leftovers (si pod redémarre)
pkill -f "code-server" || true
pkill -f "launch.py" || true
pkill -f "webui.py" || true
pkill -f nginx || true

# Ensure runpodctl (si pas installé au build)
if ! command -v runpodctl >/dev/null 2>&1; then
  curl -fsSL https://docs.runpod.io/runpodctl/install.sh | bash || true
fi

# 1) Clone A1111 dans le volume si absent
if [ ! -d "$REPO/.git" ]; then
  echo "[init] Cloning A1111 into $REPO"
  git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$REPO"
fi

# 2) Venv persistante dans /workspace
if [ ! -d "$VENV" ]; then
  echo "[init] Creating venv in $VENV"
  python -m venv "$VENV"
fi
source "$VENV/bin/activate"
pip install -U pip setuptools wheel

# 3) Pinner xformers (ton choix)
# (Torch est déjà dans l'image; xformers est dans le venv persistant)
pip install -U "xformers==0.0.29.post3" || true

# 4) Code-server (interne) + Nginx basic auth (exposé 8080)
# code-server SANS auth (il est derrière nginx)
nohup code-server --bind-addr 127.0.0.1:8443 --auth none "$WS" \
  > "$LOGDIR/code-server.log" 2>&1 &

HTPASS="$WS/.htpasswd"
USER="${CODE_USER:-user}"
PASS="${CODE_PASS:-changeme}"
htpasswd -bc "$HTPASS" "$USER" "$PASS"

cat >/etc/nginx/sites-available/default <<'NGINX'
server {
  listen 8080;
  server_name _;
  client_max_body_size 0;

  auth_basic "code-server";
  auth_basic_user_file /workspace/.htpasswd;

  location / {
    proxy_pass http://127.0.0.1:8443/;
    proxy_set_header Host $host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
NGINX

nginx -t
nginx

# 5) Lancer A1111 (sans auth) sur 7860
cd "$REPO"
A1111_ARGS_DEFAULT="--listen --port 7860 --xformers"
A1111_ARGS="${A1111_ARGS:-$A1111_ARGS_DEFAULT}"

echo "[run] A1111 args: $A1111_ARGS"
nohup python launch.py $A1111_ARGS > "$LOGDIR/a1111.log" 2>&1 &

echo ""
echo "== SERVICES =="
echo "A1111    : 7860 (no auth)"
echo "CodeSrv  : 8080 (basic auth via nginx)"
echo "Logs     : $LOGDIR/a1111.log | $LOGDIR/code-server.log"

# Keep container alive + show logs
tail -F "$LOGDIR/a1111.log"
