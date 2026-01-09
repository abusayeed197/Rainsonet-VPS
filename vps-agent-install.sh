#!/bin/bash

#############################################
# Bare Metal VPS Monitoring Agent
# Version: 1.0.0
# 
# This script installs a monitoring agent on your VPS
# that provides real-time stats and restart functionality
# to the Bare Metal VPS Dashboard.
#
# Usage: curl -sSL https://your-domain.com/install.sh | bash
#############################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/bare-metal-agent"
SERVICE_NAME="bare-metal-agent"
API_PORT=9876

# Print banner
print_banner() {
    echo -e "${RED}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║     ██████╗  █████╗ ██████╗ ███████╗    ███╗   ███╗███████╗ ║"
    echo "║     ██╔══██╗██╔══██╗██╔══██╗██╔════╝    ████╗ ████║██╔════╝ ║"
    echo "║     ██████╔╝███████║██████╔╝█████╗      ██╔████╔██║█████╗   ║"
    echo "║     ██╔══██╗██╔══██║██╔══██╗██╔══╝      ██║╚██╔╝██║██╔══╝   ║"
    echo "║     ██████╔╝██║  ██║██║  ██║███████╗    ██║ ╚═╝ ██║███████╗ ║"
    echo "║     ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝    ╚═╝     ╚═╝╚══════╝ ║"
    echo "║                                                              ║"
    echo "║              VPS Monitoring Agent Installer                  ║"
    echo "║                     Version 1.0.0                            ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: Please run as root (use sudo)${NC}"
        exit 1
    fi
}

# Generate API key
generate_api_key() {
    API_KEY=$(openssl rand -hex 32)
    echo $API_KEY
}

# Install dependencies
install_dependencies() {
    echo -e "${BLUE}[*] Installing dependencies...${NC}"
    
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq python3 python3-pip curl jq
    elif command -v yum &> /dev/null; then
        yum install -y -q python3 python3-pip curl jq
    elif command -v dnf &> /dev/null; then
        dnf install -y -q python3 python3-pip curl jq
    else
        echo -e "${RED}Error: Unsupported package manager${NC}"
        exit 1
    fi
    
    pip3 install flask psutil --quiet
    echo -e "${GREEN}[✓] Dependencies installed${NC}"
}

# Create the monitoring agent
create_agent() {
    echo -e "${BLUE}[*] Creating monitoring agent...${NC}"
    
    mkdir -p $INSTALL_DIR
    
    cat > $INSTALL_DIR/agent.py << 'AGENT_EOF'
#!/usr/bin/env python3
"""
Bare Metal VPS Monitoring Agent
Provides real-time system statistics and restart functionality
"""

import os
import json
import subprocess
from flask import Flask, jsonify, request
import psutil

app = Flask(__name__)

# Load API key from config
API_KEY = os.environ.get('BM_API_KEY', '')

def require_api_key(f):
    """Decorator to require API key authentication"""
    def decorated_function(*args, **kwargs):
        provided_key = request.headers.get('X-API-Key')
        if not provided_key or provided_key != API_KEY:
            return jsonify({'error': 'Invalid or missing API key'}), 401
        return f(*args, **kwargs)
    decorated_function.__name__ = f.__name__
    return decorated_function

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'version': '1.0.0'})

@app.route('/stats', methods=['GET'])
@require_api_key
def get_stats():
    """Get system statistics"""
    try:
        # CPU Usage
        cpu_percent = psutil.cpu_percent(interval=1)
        
        # Memory/RAM Usage
        memory = psutil.virtual_memory()
        ram_usage = memory.percent
        ram_total = round(memory.total / (1024 ** 3), 2)  # GB
        ram_used = round(memory.used / (1024 ** 3), 2)    # GB
        
        # Disk/Storage Usage
        disk = psutil.disk_usage('/')
        storage_usage = disk.percent
        storage_total = round(disk.total / (1024 ** 3), 2)  # GB
        storage_used = round(disk.used / (1024 ** 3), 2)    # GB
        
        # Uptime
        boot_time = psutil.boot_time()
        uptime_seconds = int(psutil.time.time() - boot_time)
        days = uptime_seconds // 86400
        hours = (uptime_seconds % 86400) // 3600
        minutes = (uptime_seconds % 3600) // 60
        uptime = f"{days} days, {hours} hours, {minutes} minutes"
        
        # Network stats
        net_io = psutil.net_io_counters()
        bytes_sent = round(net_io.bytes_sent / (1024 ** 3), 2)  # GB
        bytes_recv = round(net_io.bytes_recv / (1024 ** 3), 2)  # GB
        
        return jsonify({
            'status': 'success',
            'data': {
                'cpu': {
                    'usage': cpu_percent,
                    'cores': psutil.cpu_count()
                },
                'ram': {
                    'usage': ram_usage,
                    'total_gb': ram_total,
                    'used_gb': ram_used
                },
                'storage': {
                    'usage': storage_usage,
                    'total_gb': storage_total,
                    'used_gb': storage_used
                },
                'network': {
                    'sent_gb': bytes_sent,
                    'received_gb': bytes_recv
                },
                'uptime': uptime,
                'uptime_seconds': uptime_seconds
            }
        })
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/restart', methods=['POST'])
@require_api_key
def restart_vps():
    """Restart the VPS"""
    try:
        # Schedule restart in 5 seconds to allow response to be sent
        subprocess.Popen(['shutdown', '-r', '+1', 'Restart initiated from Bare Metal Dashboard'])
        return jsonify({
            'status': 'success',
            'message': 'VPS restart scheduled. The server will restart in 1 minute.'
        })
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/cancel-restart', methods=['POST'])
@require_api_key
def cancel_restart():
    """Cancel scheduled restart"""
    try:
        subprocess.run(['shutdown', '-c'], check=True)
        return jsonify({
            'status': 'success',
            'message': 'Restart cancelled successfully.'
        })
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

if __name__ == '__main__':
    port = int(os.environ.get('BM_PORT', 9876))
    app.run(host='0.0.0.0', port=port, threaded=True)
AGENT_EOF

    chmod +x $INSTALL_DIR/agent.py
    echo -e "${GREEN}[✓] Monitoring agent created${NC}"
}

# Create systemd service
create_service() {
    echo -e "${BLUE}[*] Creating systemd service...${NC}"
    
    cat > /etc/systemd/system/$SERVICE_NAME.service << SERVICE_EOF
[Unit]
Description=Bare Metal VPS Monitoring Agent
After=network.target

[Service]
Type=simple
User=root
Environment="BM_API_KEY=$API_KEY"
Environment="BM_PORT=$API_PORT"
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/agent.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME
    
    echo -e "${GREEN}[✓] Service created and started${NC}"
}

# Configure firewall
configure_firewall() {
    echo -e "${BLUE}[*] Configuring firewall...${NC}"
    
    if command -v ufw &> /dev/null; then
        ufw allow $API_PORT/tcp
        echo -e "${GREEN}[✓] UFW rule added for port $API_PORT${NC}"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$API_PORT/tcp
        firewall-cmd --reload
        echo -e "${GREEN}[✓] Firewalld rule added for port $API_PORT${NC}"
    else
        echo -e "${YELLOW}[!] No firewall detected. Please manually open port $API_PORT${NC}"
    fi
}

# Save configuration
save_config() {
    cat > $INSTALL_DIR/config.json << CONFIG_EOF
{
    "api_key": "$API_KEY",
    "port": $API_PORT,
    "version": "1.0.0",
    "installed_at": "$(date -Iseconds)"
}
CONFIG_EOF
    
    chmod 600 $INSTALL_DIR/config.json
}

# Print success message
print_success() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}║          Installation Complete!                              ║${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  IMPORTANT: Save this API Key - you'll need it for the       ║${NC}"
    echo -e "${YELLOW}║  admin panel to connect to this VPS monitoring agent.        ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}API Key:${NC} ${GREEN}$API_KEY${NC}"
    echo -e "${BLUE}Port:${NC} ${GREEN}$API_PORT${NC}"
    echo -e "${BLUE}Endpoint:${NC} ${GREEN}http://YOUR_VPS_IP:$API_PORT${NC}"
    echo ""
    echo -e "${BLUE}Service Commands:${NC}"
    echo -e "  ${GREEN}systemctl status $SERVICE_NAME${NC}  - Check status"
    echo -e "  ${GREEN}systemctl restart $SERVICE_NAME${NC} - Restart agent"
    echo -e "  ${GREEN}systemctl stop $SERVICE_NAME${NC}    - Stop agent"
    echo ""
    echo -e "${BLUE}Test the agent:${NC}"
    echo -e "  ${GREEN}curl http://localhost:$API_PORT/health${NC}"
    echo ""
    echo -e "${RED}Enter this API key in the Bare Metal Admin Panel to enable${NC}"
    echo -e "${RED}real-time monitoring and restart functionality for this VPS.${NC}"
    echo ""
}

# Uninstall function
uninstall() {
    echo -e "${YELLOW}[*] Uninstalling Bare Metal Agent...${NC}"
    
    systemctl stop $SERVICE_NAME 2>/dev/null
    systemctl disable $SERVICE_NAME 2>/dev/null
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    systemctl daemon-reload
    rm -rf $INSTALL_DIR
    
    echo -e "${GREEN}[✓] Uninstallation complete${NC}"
}

# Main installation flow
main() {
    print_banner
    
    # Check for uninstall flag
    if [ "$1" == "--uninstall" ]; then
        check_root
        uninstall
        exit 0
    fi
    
    check_root
    
    echo -e "${BLUE}[*] Starting installation...${NC}"
    echo ""
    
    # Generate API key first
    API_KEY=$(generate_api_key)
    
    install_dependencies
    create_agent
    create_service
    configure_firewall
    save_config
    
    print_success
}

# Run main function
main "$@"
