#!/bin/bash
# =============================================================================
# WhatsApp Proxy - Interactive Setup Script
# Based on: https://github.com/WhatsApp/proxy
# =============================================================================

set -e

# --- Colors & helpers --------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local answer
    if [[ "$default" == "y" ]]; then
        read -rp "$(echo -e "${CYAN}$prompt [Y/n]: ${NC}")" answer
        answer="${answer:-y}"
    else
        read -rp "$(echo -e "${CYAN}$prompt [y/N]: ${NC}")" answer
        answer="${answer:-n}"
    fi
    [[ "$answer" =~ ^[Yy] ]]
}

ask_input() {
    local prompt="$1"
    local default="$2"
    local answer
    if [[ -n "$default" ]]; then
        read -rp "$(echo -e "${CYAN}$prompt [${default}]: ${NC}")" answer
        echo "${answer:-$default}"
    else
        read -rp "$(echo -e "${CYAN}$prompt: ${NC}")" answer
        echo "$answer"
    fi
}

# --- Pre-flight checks -------------------------------------------------------
print_header "WhatsApp Proxy - Setup Script"

echo -e "This script will guide you through installing the WhatsApp proxy"
echo -e "on your VPS step by step."
echo ""
echo -e "Repository: ${BOLD}https://github.com/WhatsApp/proxy${NC}"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    print_warn "This script is not running as root."
    if ask_yes_no "Some steps require root. Continue anyway?" "n"; then
        USE_SUDO="sudo"
    else
        print_error "Please run as root: sudo bash setup-whatsapp-proxy.sh"
        exit 1
    fi
else
    USE_SUDO=""
fi

# Detect OS
print_header "Step 1/7 - System Check"

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_NAME="$NAME"
    OS_VERSION="$VERSION_ID"
    print_step "OS detected: $OS_NAME $OS_VERSION"
else
    OS_NAME="Unknown"
    print_warn "Could not detect OS. Will attempt generic installation."
fi

# Detect package manager
if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
else
    PKG_MANAGER="unknown"
fi
print_step "Package manager: $PKG_MANAGER"

# Show current IP
CURRENT_IP=$(curl -s --max-time 5 https://icanhazip.com/ 2>/dev/null || curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null || echo "not detected")
print_step "Public IP: $CURRENT_IP"

echo ""
if ! ask_yes_no "Continue with setup?"; then
    echo "Exiting."
    exit 0
fi

# --- Docker installation -----------------------------------------------------
print_header "Step 2/7 - Docker Installation"

DOCKER_INSTALLED=false
if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version 2>/dev/null)
    print_step "Docker is already installed: $DOCKER_VERSION"
    DOCKER_INSTALLED=true
else
    print_info "Docker is not installed on this system."
    echo ""
    echo "  Choose installation method:"
    echo "    1) Automatic install (official Docker script - recommended)"
    echo "    2) Manual install via package manager"
    echo "    3) Skip (I'll install Docker myself)"
    echo ""
    DOCKER_CHOICE=$(ask_input "Your choice" "1")

    case "$DOCKER_CHOICE" in
        1)
            print_info "Installing Docker via official script..."
            curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
            $USE_SUDO sh /tmp/get-docker.sh
            rm -f /tmp/get-docker.sh
            DOCKER_INSTALLED=true
            ;;
        2)
            print_info "Installing Docker via $PKG_MANAGER..."
            case "$PKG_MANAGER" in
                apt)
                    $USE_SUDO apt-get update
                    $USE_SUDO apt-get install -y docker.io docker-compose-plugin
                    ;;
                yum)
                    $USE_SUDO yum install -y docker docker-compose-plugin
                    ;;
                dnf)
                    $USE_SUDO dnf install -y docker docker-compose-plugin
                    ;;
                *)
                    print_error "Unknown package manager. Please install Docker manually."
                    exit 1
                    ;;
            esac
            DOCKER_INSTALLED=true
            ;;
        3)
            print_warn "Skipping Docker installation. Make sure to install it before running the proxy."
            ;;
    esac
fi

if [[ "$DOCKER_INSTALLED" == "true" ]]; then
    # Enable and start Docker
    if command -v systemctl &>/dev/null; then
        $USE_SUDO systemctl enable docker 2>/dev/null || true
        $USE_SUDO systemctl start docker 2>/dev/null || true
        print_step "Docker service enabled and started"
    fi
fi

# Check docker compose
COMPOSE_CMD=""
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    print_step "Docker Compose (plugin) available"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    print_step "Docker Compose (standalone) available"
else
    print_warn "Docker Compose not found."
    if ask_yes_no "Install Docker Compose standalone?"; then
        $USE_SUDO curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/bin/docker-compose
        $USE_SUDO chmod +x /usr/bin/docker-compose
        COMPOSE_CMD="docker-compose"
        print_step "Docker Compose installed"
    fi
fi

# --- Installation method ------------------------------------------------------
print_header "Step 3/7 - Installation Method"

echo "  How would you like to install WhatsApp Proxy?"
echo ""
echo "    1) Pre-built image from DockerHub (fast, recommended)"
echo "       Pulls: facebook/whatsapp_proxy:latest"
echo ""
echo "    2) Build from source (clone repo & build)"
echo "       Allows custom SSL_DNS / SSL_IP at build time"
echo ""

INSTALL_METHOD=$(ask_input "Your choice" "1")

INSTALL_DIR=""
IMAGE_NAME=""

if [[ "$INSTALL_METHOD" == "2" ]]; then
    # Clone and build
    DEFAULT_DIR="/opt/whatsapp-proxy"
    INSTALL_DIR=$(ask_input "Installation directory" "$DEFAULT_DIR")

    if [[ -d "$INSTALL_DIR/proxy" ]]; then
        print_warn "Directory $INSTALL_DIR already exists."
        if ask_yes_no "Remove and re-clone?" "n"; then
            rm -rf "$INSTALL_DIR"
        else
            print_info "Using existing directory."
        fi
    fi

    if [[ ! -d "$INSTALL_DIR" ]]; then
        print_info "Cloning repository..."
        git clone https://github.com/WhatsApp/proxy.git "$INSTALL_DIR"
        print_step "Repository cloned to $INSTALL_DIR"
    fi

    # Custom SSL settings at build time
    BUILD_ARGS=""
    if ask_yes_no "Set custom SSL domain name (SSL_DNS) at build time?" "n"; then
        SSL_DNS_VAL=$(ask_input "SSL_DNS (comma-separated domains, e.g. proxy.example.com)")
        if [[ -n "$SSL_DNS_VAL" ]]; then
            BUILD_ARGS="$BUILD_ARGS --build-arg SSL_DNS=$SSL_DNS_VAL"
        fi
    fi

    if ask_yes_no "Set custom SSL IP (SSL_IP) at build time?" "n"; then
        SSL_IP_VAL=$(ask_input "SSL_IP (comma-separated IPs, e.g. $CURRENT_IP)" "$CURRENT_IP")
        if [[ -n "$SSL_IP_VAL" ]]; then
            BUILD_ARGS="$BUILD_ARGS --build-arg SSL_IP=$SSL_IP_VAL"
        fi
    fi

    print_info "Building Docker image..."
    cd "$INSTALL_DIR"
    docker build $BUILD_ARGS proxy/ -t whatsapp_proxy:1.0
    IMAGE_NAME="whatsapp_proxy:1.0"
    print_step "Image built: $IMAGE_NAME"
else
    # Pre-built image
    print_info "Pulling pre-built image from DockerHub..."
    docker pull facebook/whatsapp_proxy:latest
    IMAGE_NAME="facebook/whatsapp_proxy:latest"
    print_step "Image pulled: $IMAGE_NAME"
fi

# --- Network configuration ----------------------------------------------------
print_header "Step 4/7 - Network Configuration"

echo -e "  WhatsApp proxy uses the following ports:"
echo ""
echo -e "  ${BOLD}Primary ports (required):${NC}"
echo "    80   - HTTP traffic"
echo "    443  - HTTPS traffic (encrypted)"
echo "    5222 - XMPP/Jabber (WhatsApp default)"
echo ""
echo -e "  ${BOLD}Media ports:${NC}"
echo "    587  - WhatsApp media (whatsapp.net)"
echo "    7777 - WhatsApp media (whatsapp.net)"
echo ""
echo -e "  ${BOLD}PROXY protocol ports (for load balancers):${NC}"
echo "    8080 - HTTP  with PROXY protocol"
echo "    8443 - HTTPS with PROXY protocol"
echo "    8222 - XMPP  with PROXY protocol"
echo ""
echo -e "  ${BOLD}Monitoring:${NC}"
echo "    8199 - HAProxy stats page"
echo ""

# Port selection
echo "  Which port set to expose?"
echo ""
echo "    1) Minimal   - 443, 587 only (best for adverse networks)"
echo "    2) Standard  - 80, 443, 5222, 587, 7777 (recommended)"
echo "    3) Full      - all ports including PROXY protocol & stats"
echo "    4) Custom    - choose ports manually"
echo ""

PORT_CHOICE=$(ask_input "Your choice" "2")

PORTS=""
case "$PORT_CHOICE" in
    1)
        PORTS="-p 443:443 -p 587:587"
        PORTS_LIST="443, 587"
        ;;
    2)
        PORTS="-p 80:80 -p 443:443 -p 5222:5222 -p 587:587 -p 7777:7777"
        PORTS_LIST="80, 443, 5222, 587, 7777"
        ;;
    3)
        PORTS="-p 80:80 -p 443:443 -p 5222:5222 -p 8199:8199 -p 8080:8080 -p 8443:8443 -p 8222:8222 -p 587:587 -p 7777:7777"
        PORTS_LIST="80, 443, 5222, 587, 7777, 8080, 8443, 8222, 8199"
        ;;
    4)
        echo ""
        print_info "Enter ports to expose (space-separated, e.g. '80 443 5222'):"
        CUSTOM_PORTS=$(ask_input "Ports" "80 443 5222 587 7777")
        PORTS=""
        PORTS_LIST=""
        for p in $CUSTOM_PORTS; do
            PORTS="$PORTS -p $p:$p"
            PORTS_LIST="${PORTS_LIST}${PORTS_LIST:+, }$p"
        done
        ;;
esac

print_step "Ports to expose: $PORTS_LIST"

# Public IP
echo ""
print_info "PUBLIC_IP is used by HAProxy to set the destination address."
print_info "If left empty, the container will auto-detect it."
echo ""

PUBLIC_IP_INPUT=$(ask_input "Public IP of this server (leave empty for auto-detect)" "$CURRENT_IP")

# --- Firewall -----------------------------------------------------------------
print_header "Step 5/7 - Firewall Configuration"

FIREWALL_TOOL=""
if command -v ufw &>/dev/null; then
    FIREWALL_TOOL="ufw"
    print_step "Detected firewall: UFW"
elif command -v firewall-cmd &>/dev/null; then
    FIREWALL_TOOL="firewalld"
    print_step "Detected firewall: firewalld"
elif command -v iptables &>/dev/null; then
    FIREWALL_TOOL="iptables"
    print_step "Detected firewall: iptables"
else
    print_warn "No known firewall detected."
fi

if [[ -n "$FIREWALL_TOOL" ]]; then
    if ask_yes_no "Open required ports in the firewall ($FIREWALL_TOOL)?"; then
        # Parse port list
        IFS=', ' read -ra PORT_ARRAY <<< "$PORTS_LIST"

        case "$FIREWALL_TOOL" in
            ufw)
                for p in "${PORT_ARRAY[@]}"; do
                    [[ -z "$p" ]] && continue
                    $USE_SUDO ufw allow "$p/tcp" && print_step "UFW: allowed port $p/tcp"
                done
                $USE_SUDO ufw reload 2>/dev/null || true
                ;;
            firewalld)
                for p in "${PORT_ARRAY[@]}"; do
                    [[ -z "$p" ]] && continue
                    $USE_SUDO firewall-cmd --permanent --add-port="$p/tcp" && print_step "firewalld: allowed port $p/tcp"
                done
                $USE_SUDO firewall-cmd --reload
                ;;
            iptables)
                for p in "${PORT_ARRAY[@]}"; do
                    [[ -z "$p" ]] && continue
                    $USE_SUDO iptables -A INPUT -p tcp --dport "$p" -j ACCEPT && print_step "iptables: allowed port $p/tcp"
                done
                print_warn "iptables rules are not persistent by default."
                print_info "Install iptables-persistent to save rules."
                ;;
        esac
        print_step "Firewall configured"
    else
        print_warn "Skipping firewall. Make sure ports are open!"
    fi
else
    print_warn "Don't forget to open these ports in your cloud provider's security group/firewall."
fi

# --- Run method ---------------------------------------------------------------
print_header "Step 6/7 - Launch Configuration"

echo "  How should the proxy run?"
echo ""
echo "    1) Docker Compose with systemd service (auto-restart on boot)"
echo "    2) Docker Compose (manual start/stop)"
echo "    3) Plain docker run (foreground, for testing)"
echo ""

RUN_METHOD=$(ask_input "Your choice" "1")

# Prepare working directory for compose
WORK_DIR="${INSTALL_DIR:-/opt/whatsapp-proxy}"
$USE_SUDO mkdir -p "$WORK_DIR" 2>/dev/null || true

case "$RUN_METHOD" in
    1|2)
        # Generate docker-compose.yml
        print_info "Generating docker-compose.yml..."

        # Build ports YAML
        PORTS_YAML=""
        IFS=', ' read -ra PORT_ARRAY <<< "$PORTS_LIST"
        for p in "${PORT_ARRAY[@]}"; do
            [[ -z "$p" ]] && continue
            PORTS_YAML="${PORTS_YAML}      - \"${p}:${p}\"\n"
        done

        ENV_SECTION=""
        if [[ -n "$PUBLIC_IP_INPUT" ]]; then
            ENV_SECTION="    environment:\n      - PUBLIC_IP=${PUBLIC_IP_INPUT}"
        fi

        cat > "$WORK_DIR/docker-compose.yml" <<DCEOF
version: '3.3'

services:
  proxy:
    container_name: whatsapp_proxy
    image: ${IMAGE_NAME}
    restart: unless-stopped
    ports:
$(echo -e "$PORTS_YAML")
    healthcheck:
      test: /usr/local/bin/healthcheck.sh
      interval: 10s
      start_period: 5s
$(if [[ -n "$PUBLIC_IP_INPUT" ]]; then echo "    environment:"; echo "      - PUBLIC_IP=${PUBLIC_IP_INPUT}"; fi)
DCEOF

        print_step "docker-compose.yml created at $WORK_DIR/docker-compose.yml"

        if [[ "$RUN_METHOD" == "1" ]] && command -v systemctl &>/dev/null; then
            # Create systemd service
            print_info "Creating systemd service..."

            cat > /tmp/whatsapp-proxy.service <<SVCEOF
[Unit]
Description=WhatsApp Proxy (Docker Compose)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${WORK_DIR}
ExecStart=$(command -v docker 2>/dev/null || echo /usr/bin/docker) compose up -d
ExecStop=$(command -v docker 2>/dev/null || echo /usr/bin/docker) compose stop
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
SVCEOF

            $USE_SUDO cp /tmp/whatsapp-proxy.service /etc/systemd/system/whatsapp-proxy.service
            $USE_SUDO systemctl daemon-reload
            $USE_SUDO systemctl enable whatsapp-proxy.service
            print_step "Systemd service created and enabled"
        fi

        # Launch
        if ask_yes_no "Start the proxy now?"; then
            print_info "Starting WhatsApp Proxy..."
            cd "$WORK_DIR"
            if [[ "$RUN_METHOD" == "1" ]]; then
                $USE_SUDO systemctl start whatsapp-proxy.service
            else
                $USE_SUDO $COMPOSE_CMD up -d
            fi
            sleep 3
            print_step "Proxy started!"
        fi
        ;;

    3)
        # Plain docker run
        ENV_FLAG=""
        if [[ -n "$PUBLIC_IP_INPUT" ]]; then
            ENV_FLAG="-e PUBLIC_IP=$PUBLIC_IP_INPUT"
        fi

        DOCKER_CMD="docker run -d --name whatsapp_proxy --restart unless-stopped $PORTS $ENV_FLAG $IMAGE_NAME"

        echo ""
        print_info "Docker command:"
        echo -e "  ${BOLD}$DOCKER_CMD${NC}"
        echo ""

        if ask_yes_no "Run this command now?"; then
            # Remove old container if exists
            docker rm -f whatsapp_proxy 2>/dev/null || true
            eval $DOCKER_CMD
            sleep 3
            print_step "Container started!"
        else
            print_info "You can run it manually later."
        fi
        ;;
esac

# --- Summary ------------------------------------------------------------------
print_header "Step 7/7 - Summary"

echo -e "  ${GREEN}${BOLD}WhatsApp Proxy setup complete!${NC}"
echo ""
echo -e "  ${BOLD}Connection info for WhatsApp app:${NC}"
echo -e "    Server: ${BOLD}${PUBLIC_IP_INPUT:-$CURRENT_IP}${NC}"
echo ""
echo -e "  ${BOLD}Stats page:${NC}"
if [[ "$PORTS_LIST" == *"8199"* ]]; then
    echo -e "    http://${PUBLIC_IP_INPUT:-$CURRENT_IP}:8199"
else
    echo -e "    (port 8199 not exposed)"
fi
echo ""
echo -e "  ${BOLD}How to connect from WhatsApp:${NC}"
echo "    1. Open WhatsApp > Settings > Storage and Data > Proxy"
echo "    2. Enable 'Use Proxy'"
echo "    3. Enter your server address: ${PUBLIC_IP_INPUT:-$CURRENT_IP}"
echo "    4. Tap 'Save'"
echo ""
echo -e "  ${BOLD}Useful commands:${NC}"

if [[ "$RUN_METHOD" == "1" ]]; then
    echo "    Status:   systemctl status whatsapp-proxy"
    echo "    Logs:     docker logs whatsapp_proxy"
    echo "    Stop:     systemctl stop whatsapp-proxy"
    echo "    Start:    systemctl start whatsapp-proxy"
    echo "    Restart:  systemctl restart whatsapp-proxy"
elif [[ "$RUN_METHOD" == "2" ]]; then
    echo "    Status:   docker ps"
    echo "    Logs:     docker logs whatsapp_proxy"
    echo "    Stop:     cd $WORK_DIR && $COMPOSE_CMD down"
    echo "    Start:    cd $WORK_DIR && $COMPOSE_CMD up -d"
else
    echo "    Status:   docker ps"
    echo "    Logs:     docker logs whatsapp_proxy"
    echo "    Stop:     docker stop whatsapp_proxy"
    echo "    Start:    docker start whatsapp_proxy"
    echo "    Remove:   docker rm -f whatsapp_proxy"
fi

echo ""
echo -e "  ${BOLD}Security tips:${NC}"
echo "    - For adverse networks, expose only ports 443 and 587"
echo "    - Make sure your cloud provider firewall allows the ports"
echo "    - The stats page (8199) has no authentication - don't expose publicly"
echo ""
print_step "Done! Enjoy your WhatsApp proxy."
echo ""
