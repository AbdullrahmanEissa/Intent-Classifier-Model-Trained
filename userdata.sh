#!/bin/bash
set -e

# 1. Variables (Replace YOUR-GITHUB-USERNAME with your actual GitHub username)
APP_DIR="/opt/intent-app"
REPO_URL="https://github.com/AbdullrahmanEissa/Intent-Classifier-Model-Trained"

# 2. Update packages & install system dependencies
apt-get update -y
apt-get install -y git python3 python3-venv python3-pip nginx

# 3. Create application directory and clone your repository
mkdir -p "$APP_DIR"
git clone "$REPO_URL" "$APP_DIR"
cd "$APP_DIR"

# 4. Set up Python virtual environment & install dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# 5. Train model if artifacts were not already committed to the repo
if [ ! -f "$APP_DIR/model/artifacts/intent_model.pkl" ]; then
    python3 model/train.py
fi

# 6. Ensure 'ubuntu' user owns the app directory so Gunicorn runs cleanly
chown -R ubuntu:ubuntu "$APP_DIR"

# 7. Configure Gunicorn systemd service
cat > /etc/systemd/system/intent_gunicorn.service << 'EOF'
[Unit]
Description=Gunicorn instance for Intent Classifier
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/intent-app
Environment="PATH=/opt/intent-app/.venv/bin"
ExecStart=/opt/intent-app/.venv/bin/gunicorn --workers 3 --bind 127.0.0.1:6000 app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 8. Configure Nginx reverse proxy (serves index.html at /, /predict, and /health)
cat > /etc/nginx/conf.d/intent_app.conf << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:6000;
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

# 9. Remove default Nginx site to avoid port 80 conflicts
rm -f /etc/nginx/sites-enabled/default

# Validate Nginx syntax before restarting
nginx -t

# 10. Start and enable services on boot
systemctl daemon-reload
systemctl enable intent_gunicorn
systemctl start intent_gunicorn
systemctl enable nginx
systemctl restart nginx
