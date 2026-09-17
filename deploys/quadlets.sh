#!/bin/bash
set -e

ISLAND_INTERFACE="enp2s0"
HEAD_NODE_IP="172.16.0.254"
CLUSTER_DOMAIN="island.openchami.local"
DHCP_START_IP="172.16.0.200"
DHCP_END_IP="172.16.0.250"
OCI_DATA_DIR="/data/oci"

echo "Configuring environment for ${CLUSTER_DOMAIN} on ${ISLAND_INTERFACE} (${HEAD_NODE_IP})..."

# Step 0: Install AWS CLI v2 standalone on SLES
echo "Installing AWS CLI v2..."
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install --update
rm -rf aws awscliv2.zip
# Verification: Run 'aws --version' to confirm the CLI is operational.

# Step 1: Update Hosts File for Certificate Trust
if ! grep -q "${CLUSTER_DOMAIN}" /etc/hosts; then
    echo "${HEAD_NODE_IP} ${CLUSTER_DOMAIN}" | sudo tee -a /etc/hosts > /dev/null
fi
# Verification: Run 'getent hosts ${CLUSTER_DOMAIN}' to verify resolution.

# Step 2: Setup Storage Directories
sudo mkdir -p ${OCI_DATA_DIR}
sudo chown -R $USER: ${OCI_DATA_DIR}
# Verification: Run 'ls -ld ${OCI_DATA_DIR}' to verify ownership and existence.

# Step 3: Install Versity S3 Gateway bypassing missing EL9 dependencies
echo "Installing Versity S3 Gateway..."
LATEST_VERSITY_URL=$(curl -s https://api.github.com/repos/openchami/versitygw-quadlet/releases/latest | jq -r '.assets[] | select(.name | endswith(".rpm")) | .browser_download_url' | head -n 1)
curl -sL "${LATEST_VERSITY_URL}" -o versitygw.rpm
sudo rpm -Uvh --nodeps ./versitygw.rpm
# Verification: Run 'rpm -q versitygw-quadlet' to verify package installation.

# Step 4: Configure OCI Registry Quadlet
sudo tee /etc/containers/systemd/registry.container > /dev/null << EOF
[Unit]
Description=Image OCI Registry
After=network-online.target
Requires=network-online.target

[Container]
ContainerName=registry
HostName=registry
Image=docker.io/library/registry:latest
Volume=${OCI_DATA_DIR}:/var/lib/registry:Z
PublishPort=5000:5000

[Service]
TimeoutStartSec=0
Restart=always

[Install]
WantedBy=multi-user.target
EOF
# Verification: Run 'test -f /etc/containers/systemd/registry.container' to confirm file creation.

# Step 5: Start Dependencies
sudo systemctl daemon-reload
sudo systemctl start registry.service
sudo systemctl enable --now versitygw-gensecrets.service
sudo systemctl start versitygw.service
sudo systemctl enable --now versitygw-bootstrap.service
# Verification: Run 'systemctl is-active registry versitygw' to confirm both services are active.

# Step 6: Install OpenCHAMI Services Release RPM
echo "Installing OpenCHAMI Release RPM..."
API_URL="https://api.github.com/repos/openchami/release/releases/latest"
RELEASE_JSON=$(curl -s "$API_URL")
RPM_URL=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name | endswith(".rpm")) | .browser_download_url' | head -n 1)
RPM_NAME=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name | endswith(".rpm")) | .name' | head -n 1)
curl -sL -o "$RPM_NAME" "$RPM_URL"
sudo rpm -Uvh --nodeps ./"$RPM_NAME"
# Verification: Run 'ls /etc/openchami/configs/' to confirm configuration files were unpacked.

# Step 7: Configure CoreDHCP for Island Interface
cat << EOF | sudo tee /etc/openchami/configs/coredhcp.yaml > /dev/null
server4:
  listen:
    - "%${ISLAND_INTERFACE}"
  plugins:
    - server_id: ${HEAD_NODE_IP}
    - dns: ${HEAD_NODE_IP}
    - router: ${HEAD_NODE_IP}
    - netmask: 255.255.255.0
    - coresmd: |
        svc_base_uri=https://${CLUSTER_DOMAIN}:8443
        ipxe_uri=http://${HEAD_NODE_IP}:8081/boot-service/bootscript
        ca_cert=/root_ca/root_ca.crt
        cache_valid=30s
        lease_time=1h
        single_port=false
    - bootloop: |
        lease_file=/tmp/coredhcp.db
        script_path=default
        lease_time=5m
        ipv4_start=${DHCP_START_IP}
        ipv4_end=${DHCP_END_IP}
EOF
# Verification: Run 'grep "${ISLAND_INTERFACE}" /etc/openchami/configs/coredhcp.yaml' to check interface binding.

# Step 8: Configure Certificates
sudo openchami-certificate-update update ${CLUSTER_DOMAIN}
# Verification: Run 'openssl x509 -in /root_ca/root_ca.crt -text -noout' to confirm CA generation.

# Step 9: Start OpenCHAMI Services
sudo systemctl start openchami.target
# Verification: Run 'systemctl is-active openchami.target' to confirm the target started successfully.

# Step 10: Install ochami CLI
CLI_URL=$(curl -s https://api.github.com/repos/OpenCHAMI/ochami/releases/latest | jq -r '.assets[] | select(.name | endswith("amd64.rpm") or endswith("x86_64.rpm")) | .browser_download_url' | head -n 1)
curl -sL "${CLI_URL}" -o ochami.rpm
sudo rpm -Uvh --nodeps ./ochami.rpm
# Verification: Run 'ochami version' to confirm the binary executes correctly.

# Step 11: Configure CLI Access
sudo ochami config cluster set --system --default island cluster.uri https://${CLUSTER_DOMAIN}:8443
sudo ochami config --system cluster set island boot-service.uri: /boot-service
# Verification: Run 'ochami config show' to verify the cluster endpoint mapping.

echo "Deployment Complete."
