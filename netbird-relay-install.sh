#!/bin/bash

set -e

#######################################
# CONFIGURE THESE BEFORE RUNNING
#######################################
# Set your relay subdomain directly (e.g., relay-sg.connect.amnezia.tech)
NETBIRD_RELAY_DOMAIN="${NETBIRD_RELAY_DOMAIN:-}"

# Set this to match your main Netbird management server's relay auth secret
NETBIRD_RELAY_AUTH_SECRET="${NETBIRD_RELAY_AUTH_SECRET:-}"
#######################################

check_docker_compose() {
  if command -v docker-compose &> /dev/null; then
      echo "docker-compose"
      return
  fi
  if docker compose --help &> /dev/null; then
      echo "docker compose"
      return
  fi
  echo "docker-compose is not installed. Please install Docker first." > /dev/stderr
  exit 1
}

read_relay_domain() {
  echo -n "Enter the relay subdomain (e.g., relay-sg.example.com): " > /dev/stderr
  read -r NETBIRD_RELAY_DOMAIN < /dev/tty
  if [ -z "$NETBIRD_RELAY_DOMAIN" ]; then
    echo "Domain cannot be empty!" > /dev/stderr
    read_relay_domain
  fi
}

read_auth_secret() {
  echo -n "Enter the NB_AUTH_SECRET from your main Netbird server: " > /dev/stderr
  read -r NETBIRD_RELAY_AUTH_SECRET < /dev/tty
  if [ -z "$NETBIRD_RELAY_AUTH_SECRET" ]; then
    echo "Auth secret cannot be empty!" > /dev/stderr
    read_auth_secret
  fi
}

initEnvironment() {
  # Prompt for missing values
  if [ -z "$NETBIRD_RELAY_DOMAIN" ]; then
    read_relay_domain
  fi

  if [ -z "$NETBIRD_RELAY_AUTH_SECRET" ]; then
    read_auth_secret
  fi

  NETBIRD_RELAY_EXPOSED_ADDRESS="rels://${NETBIRD_RELAY_DOMAIN}:443"

  DOCKER_COMPOSE_COMMAND=$(check_docker_compose)

  if [ -f docker-compose.yml ]; then
    echo "Generated files already exist. To reinitialize:"
    echo "  $DOCKER_COMPOSE_COMMAND down --volumes"
    echo "  rm -f docker-compose.yml Caddyfile relay.env"
    exit 1
  fi

  echo "Rendering configuration files..."
  renderDockerCompose > docker-compose.yml
  renderCaddyfile > Caddyfile
  renderRelayEnv > relay.env

  echo -e "\nStarting Netbird relay services...\n"
  $DOCKER_COMPOSE_COMMAND up -d
  echo -e "\nDone!\n"
  echo "========================================"
  echo "Relay URL: $NETBIRD_RELAY_EXPOSED_ADDRESS"
  echo "========================================"
  echo ""
  echo "Add this URL to your main Netbird server's relay configuration."
}

renderCaddyfile() {
  cat <<EOF
{
  debug
  servers :80,:443 {
    protocols h1 h2c h2 h3
  }
}

(security_headers) {
  header * {
    Strict-Transport-Security "max-age=3600; includeSubDomains; preload"
    X-Content-Type-Options "nosniff"
    X-Frame-Options "SAMEORIGIN"
    X-XSS-Protection "1; mode=block"
    -Server
    Referrer-Policy strict-origin-when-cross-origin
  }
}

${NETBIRD_RELAY_DOMAIN} {
  import security_headers
  reverse_proxy relay:80
}
EOF
}

renderRelayEnv() {
  cat <<EOF
NB_LOG_LEVEL=info
NB_LISTEN_ADDRESS=:80
NB_EXPOSED_ADDRESS=${NETBIRD_RELAY_EXPOSED_ADDRESS}
NB_AUTH_SECRET=${NETBIRD_RELAY_AUTH_SECRET}
EOF
}

renderDockerCompose() {
  cat <<EOF
services:
  caddy:
    image: caddy
    restart: unless-stopped
    networks: [netbird]
    ports:
      - '443:443'
      - '443:443/udp'
      - '80:80'
    volumes:
      - netbird_caddy_data:/data
      - ./Caddyfile:/etc/caddy/Caddyfile
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

  relay:
    image: netbirdio/relay:latest
    restart: unless-stopped
    networks: [netbird]
    env_file:
      - ./relay.env
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

volumes:
  netbird_caddy_data:

networks:
  netbird:
EOF
}

initEnvironment
