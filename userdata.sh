#!/bin/bash
set -e

fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

APP_DIR="/opt/intent-app"
REPO_URL="[https://github.com/AbdullrahmanEissa/Intent-Classifier-Model-Trained](https://github.com/AbdullrahmanEissa/Intent-Classifier-Model-Trained)"

apt-get update -y
apt-get install -y git python3 python3-venv python3-pip nginx

mkdir -p "$APP_DIR"
git clone "$REPO_URL" "$APP_DIR"
cd "$APP_DIR"

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

if [ ! -f "$APP_DIR/model/artifacts/intent_model.pkl" ]; then
    python3 model/train.py
fi

chown -R ubuntu:ubuntu "$APP_DIR"

cat > /etc/systemd/system/intent_gunicorn.service << 'EOF'
[Unit]
Description=Gunicorn instance for Intent Classifier
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/intent-app
Environment="PATH=/opt/intent-app/.venv/bin"
ExecStart=/opt/intent-app/.venv/bin/gunicorn --workers 2 --bind 127.0.0.1:6000 app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/nginx/conf.d/intent_app.conf << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location / {
        proxy_pass [http://127.0.0.1:6000](http://127.0.0.1:6000);
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_read_timeout 120s;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
nginx -t

systemctl daemon-reload
systemctl enable intent_gunicorn
systemctl start intent_gunicorn
systemctl enable nginx
systemctl restart nginx
