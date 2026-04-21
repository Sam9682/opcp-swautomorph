#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function
print_step() {
    echo -e "${BLUE}>${NC} ${GREEN}$1${NC}"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo -e "${BLUE}+========================================+${NC}"
echo -e "${BLUE}|${NC}   OPCP-SwAutoMorph Platform Setup    ${BLUE}|${NC}"
echo -e "${BLUE}+========================================+${NC}"
echo ""

# Install Python and pip
print_step "Installing system dependencies..."
sudo apt update > /dev/null 2>&1
sudo apt --fix-broken install -y > /dev/null 2>&1
sudo apt install -y python3 python3-pip python3-venv net-tools unzip > /dev/null 2>&1
print_success "System dependencies installed"

# Install Amazon Kiro CLI Chat
print_step "Installing Amazon Kiro CLI..."
curl -fsSL https://cli.kiro.dev/install | bash > /dev/null 2>&1
print_success "Amazon Kiro CLI installed"

# Install OVH shai
print_step "Installing OVH CLI..."
curl -fsSL https://raw.githubusercontent.com/ovh/shai/main/install.sh | sh > /dev/null 2>&1
echo 'export PATH="/home/ubuntu/.local/bin:$PATH"' >> ~/.bashrc
print_success "OVH CLI installed"

# Install AWS CLI
print_step "Installing AWS CLI..."
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install > /dev/null 2>&1
rm -rf aws awscliv2.zip
print_success "AWS CLI installed"

# Install Terraform
print_step "Installing Terraform..."
curl -s "https://releases.hashicorp.com/terraform/1.14.5/terraform_1.14.5_linux_amd64.zip" -o "terraform.zip"
unzip -q terraform.zip
sudo mv terraform /usr/local/bin/
rm -f terraform.zip
print_success "Terraform installed"

# Configure network interface priorities
print_step "Configuring network interface priorities..."
if [ -f /etc/netplan/*.yaml ]; then
    NETPLAN_FILE=$(ls /etc/netplan/*.yaml | head -1)
    sudo cp $NETPLAN_FILE ${NETPLAN_FILE}.backup
    
    # Detect interfaces and their IPs
    INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^e' | grep -v '@')
    PUBLIC_IF=""
    PRIVATE_IF=""
    
    for iface in $INTERFACES; do
        IP=$(ip -4 addr show $iface | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        if [ -n "$IP" ]; then
            # Check if IP is private (10.x, 172.16-31.x, 192.168.x)
            if [[ $IP =~ ^10\. ]] || [[ $IP =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || [[ $IP =~ ^192\.168\. ]]; then
                PRIVATE_IF=$iface
            else
                PUBLIC_IF=$iface
            fi
        fi
    done
    
    # Generate netplan config
    echo "network:" | sudo tee $NETPLAN_FILE > /dev/null
    echo "  version: 2" | sudo tee -a $NETPLAN_FILE > /dev/null
    echo "  ethernets:" | sudo tee -a $NETPLAN_FILE > /dev/null
    
    for iface in $INTERFACES; do
        echo "    $iface:" | sudo tee -a $NETPLAN_FILE > /dev/null
        echo "      dhcp4: true" | sudo tee -a $NETPLAN_FILE > /dev/null
        if [ "$iface" = "$PUBLIC_IF" ]; then
            echo "      dhcp4-overrides:" | sudo tee -a $NETPLAN_FILE > /dev/null
            echo "        route-metric: 50" | sudo tee -a $NETPLAN_FILE > /dev/null
        elif [ "$iface" = "$PRIVATE_IF" ]; then
            echo "      dhcp4-overrides:" | sudo tee -a $NETPLAN_FILE > /dev/null
            echo "        route-metric: 200" | sudo tee -a $NETPLAN_FILE > /dev/null
        fi
    done
    
    sudo netplan apply > /dev/null 2>&1
    print_success "Network priorities configured (public: 50, private: 200)"
else
    print_warning "Netplan not found, skipping network configuration"
fi

# Install Docker
print_step "Installing Docker..."
DOCKER_INSTALLED=false

# Method 1: Official apt repository (preferred, no DNS dependency on get.docker.com)
if ! command -v docker &> /dev/null; then
    sudo apt install -y ca-certificates curl gnupg > /dev/null 2>&1
    sudo install -m 0755 -d /etc/apt/keyrings
    for attempt in 1 2 3; do
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg 2>/dev/null && break
        print_warning "Docker GPG key download attempt $attempt failed, retrying in 5s..."
        sleep 5
    done
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update > /dev/null 2>&1
    if sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1; then
        DOCKER_INSTALLED=true
    fi
fi

# Method 2: Fallback to convenience script if apt method failed
if ! command -v docker &> /dev/null && [ "$DOCKER_INSTALLED" = false ]; then
    print_warning "Apt method failed, trying convenience script..."
    for attempt in 1 2 3; do
        curl -fsSL https://get.docker.com -o get-docker.sh 2>/dev/null && break
        print_warning "Download attempt $attempt failed, retrying in 5s..."
        sleep 5
    done
    if [ -f get-docker.sh ]; then
        sudo sh get-docker.sh > /dev/null 2>&1 && DOCKER_INSTALLED=true
        rm -f get-docker.sh
    fi
fi

if command -v docker &> /dev/null; then
    # Add user to docker group (group is created by the install)
    sudo usermod -aG docker $USER
    # Install docker-compose standalone only if compose plugin is missing
    if ! docker compose version &> /dev/null; then
        sudo curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
        sudo chmod +x /usr/local/bin/docker-compose
    fi
    print_success "Docker installed"
else
    print_error "Docker installation failed — check network connectivity and retry"
fi

# Configure AWS
print_step "Configuring AWS credentials..."
mkdir -p ~/.aws
cat > ~/.aws/config <<EOF
[profile OVH-SWAUTOMORPH]
region = gra
output = json
EOF

cat > ~/.aws/credentials <<EOF
[OVH-SWAUTOMORPH]
aws_access_key_id = XXX
aws_secret_access_key = YYY
endpoint_url = https://s3.gra.io.cloud.ovh.net/
signature_version = s3v4
EOF

export AWS_DEFAULT_PROFILE=OVH-SWAUTOMORPH
export AWS_ENDPOINT_URL_S3=https://s3.gra.io.cloud.ovh.net/
print_success "AWS credentials configured"

# Clone repository
print_step "Cloning OPCP-SwAutoMorph repository..."
git clone git@github.com:Sam9682/opcp-swautomorph.git > /dev/null 2>&1
cd opcp-swautomorph
git submodule update --init --recursive > /dev/null 2>&1
print_success "Repository cloned"

# Setup Python environment
print_step "Setting up Python virtual environment..."
python3 -m venv .venv
source .venv/bin/activate
pip install -q -r requirements.txt
print_success "Python environment ready"

# Final setup
print_step "Final configuration..."
mkdir -p logs
chmod +x setup_modsecurity_config.sh
print_success "Configuration complete"

echo ""
echo -e "${GREEN}[OK] Installation completed successfully!${NC}"
echo ""
print_warning "Don't forget to :"
print_warning "     - modify ./conf/deploy.ini with your platform settings, PLTF_NAME and DOMAIN values"
print_warning "     - add ssl certificate in ~/opcp-swautomorph/ssl/fullchain_domain.crt for nginx https"
print_warning "     - add ssl private key in ~/opcp-swautomorph/ssl/privateKey_domain.key for nginx https"
print_warning "     - enter aws_access_key_id & aws_secret_access_key in ~/.aws/credentials for s3 synchronization"