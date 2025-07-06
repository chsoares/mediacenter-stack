# Media Center Stack on Arch Linux

This repository contains the Docker Compose configuration for a comprehensive media center stack, designed for automated media management, downloading, and serving. The setup leverages Gluetun for VPN-protected torrenting, Plex for media serving, and the *ARR suite (Radarr, Sonarr, Lidarr, Prowlarr) for content automation.

This guide assumes you are running Arch Linux.

## Table of Contents

1.  [Prerequisites](#1-prerequisites)
    *   [Install Docker & Docker Compose](#install-docker--docker-compose)
    *   [Install NVIDIA Container Toolkit (for Plex Hardware Transcoding)](#install-nvidia-container-toolkit-for-plex-hardware-transcoding)
2.  [Directory Structure Setup](#2-directory-structure-setup)
3.  [Environment Variables (`.env` file)](#3-environment-variables-env-file)
4.  [Deploying the Stack](#4-deploying-the-stack)
    *   [Install Portainer (Optional, but Recommended)](#install-portainer-optional-but-recommended)
    *   [Deploy via Portainer](#deploy-via-portainer)
    *   [Deploy via Docker Compose CLI](#deploy-via-docker-compose-cli)
5.  [Initial Application Configuration](#5-initial-application-configuration)
    *   [Plex Media Server](#plex-media-server)
    *   [qBittorrent](#qbittorrent)
    *   [Prowlarr](#prowlarr)
    *   [Radarr](#radarr)
    *   [Sonarr](#sonarr)
    *   [Lidarr](#lidarr)
    *   [Overseerr](#overseerr)
    *   [FlareSolverr](#flaresolverr)
    *   [Unpackerr](#unpackerr)
    *   [Watchtower](#watchtower)

## 1. Prerequisites

Before deploying the media center stack, ensure your Arch Linux system is up-to-date and has the necessary tools installed.

### Install Docker & Docker Compose

We'll use `yay` for convenience, as it's common on Arch-based systems.

```bash
sudo pacman -Syu                     # Update your system
sudo pacman -S docker docker-compose # Install Docker and Docker Compose

# Enable and start the Docker daemon
sudo systemctl enable docker.service
sudo systemctl start docker.service

# Add your user to the 'docker' group to run Docker commands without sudo
# IMPORTANT: You will need to log out and log back in for this change to take effect.
sudo usermod -aG docker $USER
```

### Install NVIDIA Container Toolkit (for Plex Hardware Transcoding)

This is crucial for enabling hardware acceleration (transcoding) on your NVIDIA GPU with Plex.

```bash
# Install the NVIDIA driver and utilities (if not already installed)
# Replace `nvidia` with `nvidia-dkms` if you use a custom kernel or want DKMS support.
sudo pacman -S nvidia nvidia-utils

# Install the NVIDIA Container Toolkit from AUR using yay
yay -S nvidia-container-toolkit

# Configure Docker to use the NVIDIA runtime (this step might be automatically handled by yay, but verify)
# If the /etc/docker/daemon.json file exists, ensure it has the following:
# {
#     "default-runtime": "nvidia",
#     "runtimes": {
#         "nvidia": {
#             "path": "/usr/bin/nvidia-container-runtime",
#             "runtimeArgs": []
#         }
#     }
# }
# If it doesn't exist, create it:
# sudo nano /etc/docker/daemon.json
# Paste the content above and save.

# Restart Docker daemon to apply changes
sudo systemctl restart docker.service
```

## 2. Directory Structure Setup

The Docker Compose file expects specific host directories for configuration and media files. Create these directories and set appropriate permissions for your user.

```bash
# Create the main base directories
sudo mkdir -p /srv/mediacenter/{config,data}

# Create configuration directories for each service
sudo mkdir -p /srv/mediacenter/config/{gluetun,qbittorrent,bazarr,plex,overseerr,lidarr,prowlarr,radarr,sonarr,flaresolverr,unpackerr,watchtower,portainer}

# Create media data directories (movies, series, music, downloads, watch folder)
sudo mkdir -p /srv/mediacenter/data/{movies,tv,music,downloads/{incomplete,complete},watch}

# Set ownership and permissions.
# Replace <YOUR_USER> with your actual username (e.g., your_user).
# Use 'id -u $USER' and 'id -g $USER' to find your UID and GID.
# The PUID and PGID in your .env file MUST match these values.
sudo chown -R $USER:$USER /srv/mediacenter
sudo chmod -R 775 /srv/mediacenter
```

## 3. Environment Variables (`.env` file)

Create a `.env` file in the same directory as your `docker-compose.yml` file. This file holds sensitive information and user-specific configurations.

```bash
# Example .env content - Adjust values as per your setup.
# Place this in the root of your Docker Compose project directory.

# Name of the project in Docker
COMPOSE_PROJECT_NAME=mediacenter-stack

# Docker Network Configuration (internal to Docker, usually no change needed)
DOCKER_SUBNET=172.28.10.0/24
DOCKER_GATEWAY=172.28.10.1

# Your Local Home Network Subnet (e.g., 192.168.1.0/24, 10.0.0.0/24)
# This is used by Gluetun to allow local network access to Docker services.
LOCAL_SUBNET=10.42.42.0/24 # <--- IMPORTANT: Adjust to your actual home network subnet

# Local Docker Host IP (often not strictly needed for basic setup, keep as is)
LOCAL_DOCKER_IP=10.168.1.10 # <--- IMPORTANT: Adjust to your Arch host's actual IP

# Theme Park theme for *ARR apps (optional eye-candy)
# Refer to Theme Park for more info / options: https://docs.theme-park.dev/theme-options/
TP_THEME=plex # <--- Your preferred theme

# Host Data Folders - Must exist and have correct permissions (PUID/PGID)
# These will be mapped to /srv/mediacenter/config and /srv/mediacenter/data on your Arch host.
CONFIG_ROOT=/srv/mediacenter/config
MEDIA_ROOT=/srv/mediacenter/data

# File access, date and time details for the containers.
# IMPORTANT: Update PUID/PGID to match your host user's UID/GID.
# Run "id -u $USER" and "id -g $USER" in your Arch terminal to find them.
PUID=1000 # <--- IMPORTANT: Your User ID
PGID=1000 # <--- IMPORTANT: Your Group ID
UMASK=0002
TIMEZONE=America/Sao_Paulo # <--- IMPORTANT: Your timezone (e.g., Europe/London, America/New_York)

# VPN Connection for the entire Docker Stack (Gluetun)
# A full list of supported VPN / Wireguard providers can be found on: https://github.com/qdm12/gluetun-wiki
# VPN_TYPE options: openvpn, wireguard
VPN_TYPE=wireguard # <--- IMPORTANT: openvpn or wireguard
VPN_SERVICE_PROVIDER=windscribe # <--- IMPORTANT: Your VPN provider (e.g., windscribe, expressvpn, nordvpn)
SERVER_REGIONS=Brazil # <--- Optional: Specific region for VPN server
SERVER_COUNTRIES=
SERVER_CITIES=
SERVER_HOSTNAMES=

# OpenVPN Specifics (uncomment and fill if VPN_TYPE=openvpn)
# VPN_USERNAME=your_vpn_username
# VPN_PASSWORD=your_vpn_password
# OPENVPN_CUSTOM_CONFIG= # e.g., /gluetun/custom-openvpn.conf (relative to gluetun config volume)

# WireGuard Specifics (uncomment and fill if VPN_TYPE=wireguard)
# Get these from your VPN provider's WireGuard configuration file.
WIREGUARD_PUBLIC_KEY=c88CXfzJqasp/RIf7hQyYjrakrSyI4zfZdcTmcTwwxQ= # <--- IMPORTANT: Your WireGuard public key
WIREGUARD_PRIVATE_KEY=qK32bm+9rkbTYhxWNjsLu+VvSyCK4DgB1A5JCdhguV8= # <--- IMPORTANT: Your WireGuard private key
WIREGUARD_PRESHARED_KEY=5JpIGeslKA6t4MkJ1XZO6UOq+KUrioUhdII9F75txrg= # <--- IMPORTANT: Your WireGuard preshared key
WIREGUARD_ADDRESSES=100.69.192.106/32 # <--- IMPORTANT: Your WireGuard address
DNS_ADDRESSES=10.255.255.3 # <--- IMPORTANT: Your VPN provider's DNS (e.g., Windscribe's DNS)

# Default Ports for Web UI access (from your host, e.g., http://localhost:PORT)
# You can change these if you need, but they can't conflict with other active ports.
# Internal container ports are not changed unless specified in the image doc.
WEBUI_PORT_BAZARR=6767
WEBUI_PORT_LIDARR=8686
WEBUI_PORT_PLEX=32400
WEBUI_PORT_OVERSEERR=5055
WEBUI_PORT_PROWLARR=9696
WEBUI_PORT_QBITTORRENT=8201
WEBUI_PORT_RADARR=7878
WEBUI_PORT_SONARR=8989
WEBUI_PORT_PORTAINER=9443 # <--- For Portainer UI
WEBUI_PORT_WATCHTOWER=9000
FLARESOLVERR_PORT=8191

# Download Client Ports (internal to Gluetun, usually no changed by user)
QBIT_PORT_TCP=6881
QBIT_PORT_UDP=6881

# API Keys (will be filled by automation script, or manually if you prefer)
# These are used by other services (e.g., Unpackerr) to communicate with *ARR apps.
RADARR_API_KEY=fd222b27217d460b81e5d5a5e2a31665 # <--- Will be updated from Radarr's settings
SONARR_API_KEY=f31856e7b4824f6ea0a674507e27814e # <--- Will be updated from Sonarr's settings
LIDARR_API_KEY=a39b2d8da5eb4fd385efa9d813bfed90 # <--- Will be updated from Lidarr's settings
OVERSEERR_API_KEY= # <--- Will be updated from Overseerr's settings
```

## 4. Deploying the Stack

You can deploy the stack using Portainer (recommended for GUI management) or directly via Docker Compose CLI.

### Install Portainer (Optional, but Recommended)

Portainer provides a web-based GUI to manage your Docker containers, volumes, networks, and stacks.

```bash
# Create Portainer data volume
docker volume create portainer_data

# Run Portainer container
docker run -d -p ${WEBUI_PORT_PORTAINER}:9000 \
    --name portainer --restart unless-stopped \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest
```

Access Portainer at `http://<YOUR_ARCH_HOST_IP>:${WEBUI_PORT_PORTAINER}` (e.g., `http://localhost:9443`). On first run, it will ask you to create an admin user.

### Deploy via Portainer

1.  Access your Portainer UI (e.g., `http://localhost:9443`).
2.  Navigate to **"Stacks"** in the left sidebar.
3.  Click **"Add stack"**.
4.  **Name:** Enter `mediacenter-stack` (or any name you prefer).
5.  **Build method:** Select **"Web editor"**.
6.  **Copy and paste the entire content of your `docker-compose.yml` file into the web editor.**
7.  **Environment variables:** Crucially, if you didn't define `.env` directly in Portainer (which is ideal for local `.env` files), you might need to manually set the environment variables here, or ensure Portainer can read them. For a simpler approach, ensure your `docker-compose.yml` and `.env` are in the same directory, and deploy from CLI first to test. Portainer can then import it.
    *   **Better way:** Put your `docker-compose.yml` and `.env` files in a local directory on your Arch host. In Portainer, go to **"Stacks" -> "Add stack"**. Choose **"Git Repository"** or **"Upload"** if you want to keep them managed there, or specify **"Compose file path"** to point to your local directory (requires Docker volume mapping for Portainer agent if on remote host, or host bind if Portainer is on the same host).
    *   **Simplest for now:** Ensure the `docker-compose.yml` and `.env` are in `/srv/mediacenter/` on your Arch host.
        *   In Portainer, choose **"Git Repository"** and point it to your repo, or simply **"Copy/Paste"** the `docker-compose.yml` content into the web editor. You'll need to manually set *all* the `.env` variables directly in the Portainer stack configuration if you copy/paste.
        *   **Recommendation:** Use the CLI for the initial deployment, as it naturally picks up the `.env` file. Then, Portainer will automatically discover the running stack.

8.  Click **"Deploy the stack"**.

### Deploy via Docker Compose CLI

Navigate to the directory containing your `docker-compose.yml` and `.env` files (e.g., `/srv/mediacenter/` if you moved them there).

```bash
# Navigate to your project directory
cd /srv/mediacenter/ # Or wherever you placed your files

# Pull the latest images
docker compose pull

# Build and start the containers in detached mode
docker compose up -d

# Check the status of your containers
docker compose ps
```

You can monitor the logs of individual containers using `docker logs <container_name>`. For example, `docker logs gluetun`.

## 5. Initial Application Configuration

After the stack is up and running, you'll need to configure each application through its web UI. Remember to replace `<YOUR_ARCH_HOST_IP>` with the actual IP address of your Arch Linux machine where Docker is running.

### Plex Media Server

**Access:** `http://<YOUR_ARCH_HOST_IP>:${WEBUI_PORT_PLEX}` (e.g., `http://localhost:32400`)

1.  **Claim Server:** Follow the initial setup wizard to claim your Plex server to your Plex account.
2.  **Add Libraries:**
    *   Click the `+` next to "Libraries".
    *   Select "Movies", point to `/movies`.
    *   Select "TV Shows", point to `/tv`.
    *   Select "Music", point to `/music`.
    *   Ensure "Scan my library automatically" is enabled.
    *   **Note:** These paths (`/movies`, `/tv`, `/music`) are *inside the Plex container*. They map to `/srv/mediacenter/data/movies`, etc., on your host.

### qBittorrent

**Access:** `http://<YOUR_ARCH_HOST_IP>:${WEBUI_PORT_QBITTORRENT}` (e.g., `http://localhost:8201`)

1.  **Initial Login:** Default username is `admin`, default password is `adminadmin` (change immediately!).
2.  **Web UI:** You might want to enable dark mode or customize the UI.
3.  **Downloads:**
    *   Go to `Tools > Options > Downloads`.
    *   **Save files to location:** `/downloads/complete`
    *   **Temporary download location:** `/downloads/incomplete`
    *   **Optional:** Enable "Append .!qB extension to incomplete files".
    *   **Important:** `Category` setup for Radarr/Sonarr/Lidarr to deposit files. (e.g., `movies`, `tv`, `music`).

### Prowlarr

**Access:** `http://<YOUR_ARCH_HOST_IP>:${WEBUI_PORT_PROWLARR}` (e.g., `http://localhost:9696`)

1.  **Initial Setup:** If prompted, create an admin account.
2.  **API Key:** Go to `Settings > General` and note your API Key. You'll need this for Radarr, Sonarr, and Lidarr.
3.  **Add Indexers:**
    *   Go to `Indexers`. Click `+ Add new Indexer`.
    *   Browse and add your preferred public or private torrent trackers (e.g., The Pirate Bay, RARBG, or specific private trackers you have access to).
    *   Fill in the required details (API Key, username/password for private trackers).
    *   **Crucial:** After adding, click the **"Test"** button for each indexer to ensure Prowlarr can connect.
4.  **Add Applications:**
    *   Go to `Applications`. Click `+ Add new Application`.
    *   **Add Radarr:**
        *   **Application:** Radarr
        *   **Name:** Radarr
        *   **Sync Categories:** Check this.
        *   **URL:** `http://radarr:7878` (Use the service name, not localhost)
        *   **API Key:** Get this from Radarr's `Settings > General`.
        *   **Test & Save**.
    *   Repeat for Sonarr, Lidarr, and Bazarr (if you enable it later).

### Radarr

**Access:** `http://<YOUR_ARCH_HOST_IP>:${WEBUI_PORT_RADARR}` (e.g., `http://localhost:7878`)

1.  **Initial Setup:** Complete any initial wizard.
2.  **API Key:** Go to `Settings > General` and note your API Key.
3.  **Add Download Client (qBittorrent):**
    *   Go to `Settings > Download Clients`. Click `+`.
    *   **Type:** `qBittorrent`
    *   **Name:** `qBittorrent`
    *   **Host:** `gluetun` (Radarr talks to qBittorrent via Gluetun)
    *   **Port:** `${WEBUI_PORT_QBITTORRENT}` (e.g., `8201`)
    *   **Username/Password:** If configured in qBittorrent.
    *   **Category:** `movies` (important for qBittorrent organization)
    *   **Remote Path Mappings:** **CRITICAL!**
        *   Click `+ Add new mapping`.
        *   **Host:** `gluetun`
        *   **Remote Path:** `/downloads` (This is qBittorrent's internal path)
        *   **Local Path:** `/data/downloads` (This is Radarr's internal path to the *same data*)
    *   **Test & Save**. Ensure "Test Successful".

4.  **Add Indexers (Prowlarr):**
    *   Go to `Settings > Indexers`. Click `+`.
    *   **Type:** `Prowlarr`
    *   **Name:** `Prowlarr`
    *   **URL:** `http://prowlarr:9696`
    *   **API Key:** Get this from Prowlarr's `Settings > General`.
    *   **Test & Save**. Ensure "Test Successful".

5.  **Add Root Folder:**
    *   Go to `Settings > Media Management`. Scroll to `Root Folders`.
    *   Click `+ Add Root Folder`.
    *   Browse and select `/data/movies`.
    *   **Note:** This is where Radarr will move and organize completed movie downloads.

### Sonarr

**Access:** `http://<YOUR_ARCH_HOST_IP>:${WEBUI_PORT_SONARR}` (e.g., `http://localhost:8989`)

(Configuration steps are very similar to Radarr, but for TV Shows)

1.  **API Key:** `Settings > General`.
2.  **Download Client (qBittorrent):**
    *   `Settings > Download Clients`.
    *   **Host:** `gluetun`, **Port:** `${WEBUI_PORT_QBITTORRENT}`.
    *   **Category:** `tv`
    *   **Remote Path Mappings:**
        *   **Host:** `gluetun`
        *   **Remote Path:** `/downloads`
        *   **Local Path:** `/data/downloads`
    *   **Test & Save**.
3.  **Indexers (Prowlarr):**
    *   `Settings > Indexers`.
    *   **Type:** `Prowlarr`
    *   **URL:** `http://prowlarr:9696`
    *   **API Key:** From Prowlarr.
    *   **Test & Save**.
4.  **Root Folder:**
    *   `Settings > Media Management`. Scroll to `Root Folders`.
    *   Browse and select `/data/tv`.

### Lidarr

**Access:** `http://<YOUR_ARCH_HOST_IP>:${WEBUI_PORT_LIDARR}` (e.g., `http://localhost:8686`)

(Configuration steps are very similar to Radarr/Sonarr, but for Music)

1.  **API Key:** `Settings > General`.
2.  **Download Client (qBittorrent):**
    *   `Settings > Download Clients`.
    *   **Host:** `gluetun`, **Port:** `${WEBUI_PORT_QBITTORRENT}`.
    *   **Category:** `music`
    *   **Remote Path Mappings:**
        *   **Host:** `gluetun`
        *   **Remote Path:** `/downloads`
        *   **Local Path:** `/data/downloads`
    *   **Test & Save**.
3.  **Indexers (Prowlarr):**
    *   `Settings > Indexers`.
    *   **Type:** `Prowlarr`
    *   **URL:** `http://prowlarr:9696`
    *   **API Key:** From Prowlarr.
    *   **Test & Save**.
4.  **Root Folder:**
    *   `Settings > Media Management`. Scroll to `Root Folders`.
    *   Browse and select `/data/music`.

### Overseerr

**Access:** `http://<YOUR_ARCH_HOST_IP>:${WEBUI_PORT_OVERSEERR}` (e.g., `http://localhost:5055`)

1.  **Initial Setup:** Follow the wizard to create an admin account.
2.  **Plex Connection:**
    *   Go to `Settings > Plex`.
    *   Sign in with your Plex account. Overseerr will discover your Plex Media Server (the `plex` service in your stack).
    *   Select your Plex server and library. Enable "Sync Libraries".
3.  **Connect to *ARR Apps:**
    *   Go to `Settings > Radarr`. Enable and provide `http://radarr:7878` and Radarr's API Key. Test & Save.
    *   Go to `Settings > Sonarr`. Enable and provide `http://sonarr:8989` and Sonarr's API Key. Test & Save.
    *   Go to `Settings > Lidarr`. Enable and provide `http://lidarr:8686` and Lidarr's API Key. Test & Save.
4.  **Users:** Configure user authentication (Plex integration, local users, etc.) for requests.

### FlareSolverr

**Access:** `http://<YOUR_ARCH_HOST_IP>:${FLARESOLVERR_PORT}` (e.g., `http://localhost:8191`)

FlareSolverr usually doesn't require direct manual configuration unless you need to debug. It works as a proxy for Prowlarr (and other *ARRs if configured) to bypass Cloudflare protection on some indexers.

*   **Integration:** In Prowlarr, when adding or editing an indexer that uses Cloudflare, you can often specify "FlareSolverr" as a proxy.
    *   In Prowlarr, go to `Settings > Indexers`.
    *   When editing an indexer, you might see an option like "FlareSolverr URL". Set it to `http://flaresolverr:8191`.
    *   **Test** the indexer to ensure it works through FlareSolverr.

### Unpackerr

Unpackerr runs in the background and primarily communicates with your *ARR apps via API to report download status and trigger imports. It handles unpacking archives (`.rar`, `.zip`, etc.) automatically.

*   **No Web UI:** Unpackerr does not have a web interface.
*   **Configuration:** Its configuration is primarily via environment variables in the `docker-compose.yml`. You've already set this up correctly to point to `http://sonarr:8989`, `http://radarr:7878`, etc., using their service names.
*   **API Keys:** Ensure `SONARR_API_KEY`, `RADARR_API_KEY`, `LIDARR_API_KEY` are correctly set in your `.env` file (you'll get these from the *ARR apps' general settings).

### Watchtower

Watchtower automatically updates your running Docker containers to their latest images.

*   **No Web UI:** Watchtower does not have a web interface for its primary function.
*   **Monitoring:** You can check Watchtower's activity by viewing its Docker logs: `docker logs watchtower`.
*   **Configuration:** Your `docker-compose.yml` sets its update interval (`WATCHTOWER_POLL_INTERVAL`) and to clean up old images (`WATCHTOWER_CLEANUP=true`). No further configuration is usually needed.

---

Este `README.md` cobre a instalação, setup de diretórios, variáveis de ambiente, deploy e as configurações iniciais de cada app. É um ótimo ponto de partida!

Revise-o para ter certeza de que todos os caminhos e valores padrão fazem sentido para você e seu ambiente específico. Por exemplo, ajuste os placeholders como `<YOUR_ARCH_HOST_IP>`.

Podemos refinar qualquer seção ou adicionar mais detalhes conforme avançamos na configuração! Qual o próximo app que você gostaria de configurar? (Sonarr ou Lidarr geralmente vêm a seguir, pois são muito parecidos com o Radarr).
