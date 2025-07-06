#!/bin/bash

# --- Color Codes for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Script Configuration ---
SCRIPT_DIR=$(dirname "$(realpath "$0")")
ENV_FILE="${SCRIPT_DIR}/.env"

# --- Load Environment Variables ---
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}[!] ERROR:${NC} .env file not found at ${ENV_FILE}. Please ensure it exists."
    exit 1
fi
echo -e "${BLUE}[>] Loading environment variables from ${ENV_FILE}...${NC}"
set -a # Automatically export all variables that are defined or modified
. "$ENV_FILE"
set +a # Turn off automatic export

CONFIG_ROOT="${CONFIG_ROOT:-/srv/mediacenter/config}" # Fallback if CONFIG_ROOT is not set in .env

# --- Collected API Keys ---
declare -A COLLECTED_API_KEYS

# --- Function: extract_and_update_arr_api_key ---
# Extracts API Key from *ARR apps and updates the .env file.
function extract_and_update_arr_api_key {
    local service_name="$1" # e.g., "radarr"
    local config_path="${CONFIG_ROOT}/${service_name}/config.xml"
    local container_name_upper="${service_name^^}_API_KEY" # e.g., RADARR_API_KEY

    echo -e "${CYAN}[*] Processing ${service_name}...${NC}"

    # Wait for config.xml to be created by the container
    until [ -f "$config_path" ]; do
        echo -e "${YELLOW}[!] Waiting for ${service_name}'s config file (${config_path})... (container might still be initializing)${NC}"
        sleep 5
    done
    echo -e "${GREEN}[+] Config file found for ${service_name}.${NC}"

    # Extract API Key using sed
    local api_key=$(sed -n 's/.*<ApiKey>\(.*\)<\/ApiKey>.*/\1/p' "$config_path" | head -n 1)

    if [ -z "$api_key" ]; then
        echo -e "${YELLOW}[!] Warning:${NC} API Key NOT FOUND in ${service_name}'s config.xml. You might need to check its UI or run the script again."
    else
        echo -e "${GREEN}[+] API Key found for ${service_name}: ${api_key}${NC}"
        COLLECTED_API_KEYS["$container_name_upper"]="$api_key" # Store key

        # Update .env file using sed
        if grep -q "^${container_name_upper}=" "$ENV_FILE"; then
            echo -e "${BLUE}[>] Updating ${container_name_upper} in .env...${NC}"
            # Use | as delimiter for sed to avoid issues with / in API keys/paths
            sed -i.bak 's|^'"${container_name_upper}"'=.*|'"${container_name_upper}"'='"$api_key"'|' "$ENV_FILE" && rm "${ENV_FILE}.bak"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[+] Successfully updated ${container_name_upper} in .env.${NC}"
            else
                echo -e "${RED}[!] ERROR:${NC} Failed to update ${container_name_upper} in .env. Check permissions or sed syntax."
            fi
        else
            echo -e "${YELLOW}[!] Warning:${NC} Variable ${container_name_upper} not found as a placeholder in .env. Please add it manually if needed."
        fi
    fi

    echo -e "${BLUE}[>] Restarting ${service_name} container to apply potential new API Key or config...${NC}"
    docker compose -f docker-compose.yml -p "${COMPOSE_PROJECT_NAME}" --env-file "$ENV_FILE" restart "$service_name"
    echo -e "${GREEN}[+] ${service_name} restarted.${NC}"
    echo ""
}

# --- Function: setup_qbittorrent_password ---
# Sets a default password for qBittorrent WebUI.
function setup_qbittorrent_password {
    local service_name="$1"
    local config_path="${CONFIG_ROOT}/${service_name}/qBittorrent/qBittorrent.conf"
    local QBIT_PASSWORD_HASH='@ByteArray(ARQ77eY1NUZaQsuDHbIMCA==:0WMRkYTUWVT9wVvdDtHAjU9b3b7uB8NR1Gur2hmQCvCDpm39Q+PsJRJPaCU51dEiz+dTzh8qbPsL8WkFljQYFQ==)' # admin/adminadmin

    echo -e "${CYAN}[*] Checking ${service_name} for default password setup...${NC}"

    # Stop container to safely edit config
    echo -e "${BLUE}[>] Stopping ${service_name} to apply configurations...${NC}"
    docker compose -f docker-compose.yml -p "${COMPOSE_PROJECT_NAME}" --env-file "$ENV_FILE" stop "$service_name"

    # Wait for config file
    until [ -f "$config_path" ]; do
        echo -e "${YELLOW}[!] Waiting for ${service_name} config file (${config_path})... (container might still be initializing)${NC}"
        sleep 5
    done
    echo -e "${GREEN}[+] ${service_name} config file found.${NC}"

    # Check if password already exists
    if ! grep -q "WebUI\\\\Password_PBKDF2" "$config_path"; then
        echo -e "${BLUE}[>] Setting default password 'adminadmin' for ${service_name} WebUI...${NC}"
        sed -i.bak '/WebUI\\ServerDomains=*/a WebUI\\Password_PBKDF2='"$QBIT_PASSWORD_HASH"'' "$config_path" && rm "${config_path}.bak"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[+] Successfully set default password for ${service_name}.${NC}"
        else
            echo -e "${RED}[!] ERROR:${NC} Failed to set default password for ${service_name}. Check permissions or sed syntax."
        fi
    else
        echo -e "${YELLOW}[!] Default password already exists for ${service_name}, skipping.${NC}"
    fi

    echo -e "${BLUE}[>] Starting ${service_name} container...${NC}"
    docker compose -f docker-compose.yml -p "${COMPOSE_PROJECT_NAME}" --env-file "$ENV_FILE" start "$service_name"
    echo -e "${GREEN}[+] ${service_name} started.${NC}"
    echo ""
}

# --- Main Execution Flow ---
# Ensure containers are running and healthy
echo -e "${BLUE}[>] Checking if containers are running and healthy. This may take a few moments...${NC}"
docker compose -f docker-compose.yml -p "${COMPOSE_PROJECT_NAME}" --env-file "$ENV_FILE" up -d --wait --timeout 300 
if [ $? -ne 0 ]; then
    echo -e "${RED}[!] ERROR:${NC} Not all containers started correctly or became healthy within the timeout. Please check logs and resolve issues before running the script again."
    exit 1
fi
echo -e "${GREEN}[+] All main containers are up and running!${NC}"
echo ""

# Iterate and configure selected services
echo -e "${PURPLE}[!] Starting configuration for individual applications...${NC}"

# Configure *ARR apps (extract API keys, update .env, restart)
ARR_SERVICES=("radarr" "sonarr" "lidarr" "prowlarr")
for service in "${ARR_SERVICES[@]}"; do
    extract_and_update_arr_api_key "$service"
done

# Configure qBittorrent (set password)
setup_qbittorrent_password "qbittorrent"

# Restart Unpackerr to pick up new API keys from .env
echo -e "${CYAN}[*] Restarting Unpackerr to pick up updated API Keys from .env...${NC}"
docker compose -f docker-compose.yml -p "${COMPOSE_PROJECT_NAME}" --env-file "$ENV_FILE" restart unpackerr
echo -e "${GREEN}[+] Unpackerr restarted.${NC}"
echo ""

# --- Final Instructions ---
echo -e "${YELLOW}!!! IMPORTANT NEXT STEPS !!!${NC}"
echo ""

# Print .env content for Portainer
echo -e "${GREEN}2. UPDATE YOUR STACK IN PORTAINER"
echo -e "${CYAN}   Go to Portainer (https://localhost:${WEBUI_PORT_PORTAINER:-9443}), navigate to 'Stacks',${NC}"
echo -e "${CYAN}   click on 'mediacenter-stack', then click 'Editor'.${NC}"
echo -e "${CYAN}   Scroll down to the 'Environment variables' section (usually a large text box).${NC}"

echo ""
echo -e "${YELLOW}   Copy the ENTIRE CONTENT below and paste it into the appropriate section in Portainer:${NC}"
echo ""
cat "$ENV_FILE" | grep API_KEY
echo ""
echo -e "${YELLOW}   After pasting/updating in Portainer, scroll down and click 'Update the stack' to apply changes.${NC}"
echo ""

# Manual configuration reminders
echo -e "${GREEN}3. MANUAL CONFIGURATION IN WEB INTERFACES (Access via your browser):${NC}"
echo -e "${CYAN}   - qBittorrent (http://localhost:${WEBUI_PORT_QBITTORRENT:-8201}):${NC} Login (admin/adminadmin) and ${RED}IMMEDIATELY CHANGE THE DEFAULT PASSWORD.${NC}"
echo -e "${CYAN}   - Plex (http://localhost:${WEBUI_PORT_PLEX:-32400}/web):${NC} Claim your server, add media libraries (map to /movies, /tv, /music inside Plex), and enable Hardware Transcoding (Settings -> Transcoder)."
echo -e "${CYAN}   - Overseerr (http://localhost:${WEBUI_PORT_OVERSEERR:-5055}):${NC} Connect to Plex, then connect to Radarr/Sonarr using their API Keys (from your .env)."
echo -e "${CYAN}   - Prowlarr (http://localhost:${WEBUI_PORT_PROWLARR:-9696}):${NC} Add your indexers. Then add Prowlarr as an indexer in Radarr/Sonarr/Lidarr (inside each *ARR app)."
echo -e "${CYAN}   - Radarr/Sonarr/Lidarr (e.g., http://localhost:${WEBUI_PORT_RADARR:-7878} for Radarr):${NC} Configure download clients (qBittorrent) and indexers (Prowlarr)."
echo -e "${CYAN}   - Ensure Root Folders are set correctly (e.g., /data/movies, /data/tv, /data/music inside the *ARR app) and download clients use /data/downloads (inside the *ARR app) for completed downloads.${NC}"
echo ""
echo -e "${GREEN}Enjoy your self-hosted media stack!${NC}"
