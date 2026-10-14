#!/bin/bash
# First boot only: build the app image from the repo and start it behind
# Caddy. Both containers use --restart unless-stopped and docker is
# enabled, so a reboot brings the site back without re-running this.
set -euxo pipefail

dnf install -y docker git
systemctl enable --now docker

# 1 GB of RAM is tight for compiling mysqlclient during the image build.
fallocate -l 1G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile swap swap defaults 0 0' >> /etc/fstab

git clone --depth 1 --branch "${git_ref}" "${repo_url}" /opt/appointments/src
docker build -t appointments:local /opt/appointments/src

# SQLite on the host so bookings survive container restarts. Django's
# settings fall back to SQLite when no DATABASE_* variables are set. An
# empty file is a valid empty SQLite database.
mkdir -p /opt/appointments/data
touch /opt/appointments/data/db.sqlite3

# Generated once on the instance, never in Terraform state or the repo.
openssl rand -hex 32 > /opt/appointments/secret_key
chmod 600 /opt/appointments/secret_key
DJANGO_SECRET_KEY=$(cat /opt/appointments/secret_key)

docker network create web

# AWS_DEFAULT_REGION is needed even here: migrate's system checks import
# the views, which create a boto3 DynamoDB client at module level.
docker run --rm \
  -v /opt/appointments/data/db.sqlite3:/app/db.sqlite3 \
  -e DJANGO_SECRET_KEY="$DJANGO_SECRET_KEY" \
  -e AWS_DEFAULT_REGION="${aws_region}" \
  appointments:local manage.py migrate --noinput

docker run -d --name app --network web --restart unless-stopped \
  -v /opt/appointments/data/db.sqlite3:/app/db.sqlite3 \
  -e DJANGO_SECRET_KEY="$DJANGO_SECRET_KEY" \
  -e AWS_DEFAULT_REGION="${aws_region}" \
  appointments:local

# The domain block gets a Let's Encrypt certificate once DNS points here
# (point_dns = true). The IP block is plain HTTP for checking the app
# before cutover.
mkdir -p /opt/appointments/caddy
cat > /opt/appointments/caddy/Caddyfile <<'EOF'
${domain_name} {
	reverse_proxy app:8088
}

http://${public_ip} {
	reverse_proxy app:8088
}
EOF

docker run -d --name caddy --network web --restart unless-stopped \
  -p 80:80 -p 443:443 \
  -v /opt/appointments/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v caddy_data:/data \
  caddy:2.8.4
