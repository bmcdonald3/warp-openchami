### Step 1: Host Preparation & Package Installation

Register the SLES head node to access official repositories, then install Podman and the required utilities.

```bash
# Register the system (skip if using a local ISO mount for offline air-gapped setups)
sudo SUSEConnect -r <Your_Registration_Code> -e <Your_Email_Address>

# Refresh repositories and install dependencies
sudo zypper refresh
sudo zypper install -y podman curl jq bind-utils aws-cli squashfs-tools

# Create the required storage paths and configuration directories
sudo mkdir -p /data/oci /data/boot-images /etc/containers/systemd /etc/coredhcp /etc/haproxy

# Enable IPv4 forwarding on the head node for the island networks
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/90-forward.conf
sudo sysctl --system

```

### Step 2: Retrieve the Compute Node MAC Address

Query your compute node's BMC to fetch the MAC address. Replace `ADMIN:PASSWORD` with your actual Redfish credentials.

```bash
# Query the BMC (172.24.0.3) for the primary interface MAC
COMPUTE_MAC=$(curl -s -k -u ADMIN:PASSWORD https://172.24.0.3/redfish/v1/Systems/1/EthernetInterfaces/1 | jq -r '.MACAddress')
echo $COMPUTE_MAC

```

*(Substitute `<MAC_ADDRESS>` with this output in later steps).*

### Step 3: Install and Initialize VersityGW

Use the official OpenCHAMI VersityGW RPM to handle IAM bootstrapping and secret generation automatically.

```bash
# Download the latest release RPM
RPM_URL=$(curl -s https://api.github.com/repos/openchami/versitygw-quadlet/releases/latest | grep "browser_download_url.*\.rpm" | grep -v "\.src\.rpm" | cut -d '"' -f 4)
curl -LO $RPM_URL

# Install the RPM
sudo zypper install -y --allow-unsigned-rpm ./versitygw-quadlet-*.noarch.rpm

# Copy the RPM-provided Quadlet to the location SLES monitors
sudo cp /usr/share/containers/systemd/versitygw.container /etc/containers/systemd/
sudo systemctl daemon-reload

# Execute the initialization sequence
sudo systemctl enable --now versitygw-gensecrets.service
sudo systemctl start versitygw.service
sudo systemctl enable --now versitygw-bootstrap.service

```

### Step 4: Define the OpenCHAMI Podman Quadlets

Create the following files inside `/etc/containers/systemd/`. These include the `[Install]` section required for standard `systemctl enable` behavior.

**1. Podman Network (`/etc/containers/systemd/openchami.network`)**

```ini
[Unit]
Description=OpenCHAMI Internal Network

[Network]
NetworkName=openchami

[Install]
WantedBy=multi-user.target

```

**2. PostgreSQL Database (`/etc/containers/systemd/postgres.container`)**

```ini
[Unit]
Description=PostgreSQL for OpenCHAMI SMD
After=network-online.target

[Container]
ContainerName=postgres
Image=docker.io/library/postgres:15-alpine
Network=openchami.network
Environment=POSTGRES_USER=smd
Environment=POSTGRES_PASSWORD=smd_secret
Environment=POSTGRES_DB=smd
Volume=postgres-data:/var/lib/postgresql/data

[Install]
WantedBy=multi-user.target

```

**3. State Management Database / SMD (`/etc/containers/systemd/smd.container`)**

```ini
[Unit]
Description=OpenCHAMI SMD Microservice
After=postgres.service

[Container]
ContainerName=smd
Image=ghcr.io/openchami/smd:latest
Network=openchami.network
PublishPort=27779:27779
Environment=DB_USER=smd
Environment=DB_PASSWORD=smd_secret
Environment=DB_HOST=postgres
Environment=DB_PORT=5432
Environment=DB_NAME=smd

[Install]
WantedBy=multi-user.target

```

**4. Boot-Service (`/etc/containers/systemd/boot-service.container`)**

```ini
[Unit]
Description=OpenCHAMI Boot Service
After=smd.service

[Container]
ContainerName=boot-service
Image=ghcr.io/openchami/boot-service:latest
Network=openchami.network
PublishPort=27777:27777
Environment=SMD_URL=http://172.23.0.1:27779

[Install]
WantedBy=multi-user.target

```

**5. CoreDHCP (`/etc/containers/systemd/coredhcp.container`)**

```ini
[Unit]
Description=OpenCHAMI CoreDHCP Service
After=smd.service boot-service.service

[Container]
ContainerName=coredhcp
Image=ghcr.io/openchami/coredhcp:latest
Network=host
Volume=/etc/coredhcp/config.yml:/etc/coredhcp/config.yml:ro

[Install]
WantedBy=multi-user.target

```

**6. HAProxy API Gateway (`/etc/containers/systemd/openchami-haproxy.container`)**
*Note: This file is prefixed with `openchami-` to prevent systemd from applying native host HAProxy override drops-ins.*

```ini
[Unit]
Description=OpenCHAMI HAProxy Gateway
After=network-online.target

[Container]
ContainerName=haproxy
Image=docker.io/library/haproxy:2.8-alpine
Network=openchami.network
PublishPort=80:80
Volume=/etc/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro

[Install]
WantedBy=multi-user.target

```

### Step 5: Configure Core Services

**1. CoreDHCP Configuration**
Configure CoreDHCP to listen on `bond0` (172.23.0.1) and pass queries to SMD and the Boot Service.

```bash
sudo tee /etc/coredhcp/config.yml > /dev/null << EOF
server4:
  listen: 172.23.0.1
  plugins:
    - server_id: 172.23.0.1
    - router: 172.23.0.1
    - netmask: 255.255.0.0
    - dns: 172.23.0.1
    - coresmd: http://172.23.0.1:27779 http://172.23.0.1:27777
EOF

```

**2. HAProxy Routing Configuration**
Configure routes to the backend services. S3 traffic points to VersityGW on port 7070.

```bash
sudo tee /etc/haproxy/haproxy.cfg > /dev/null << EOF
defaults
    mode http
    timeout client 10s
    timeout connect 5s
    timeout server 10s
    timeout http-request 10s

frontend api_gateway
    bind *:80
    acl is_smd path_beg /apis/smd
    acl is_bss path_beg /apis/bss
    acl is_s3 path_beg /s3
    
    use_backend smd_backend if is_smd
    use_backend bss_backend if is_bss
    use_backend s3_backend if is_s3

backend smd_backend
    http-request replace-path /apis/smd(/)?(.*) /\2
    server smd 172.23.0.1:27779

backend bss_backend
    http-request replace-path /apis/bss(/)?(.*) /\2
    server boot-service 172.23.0.1:27777

backend s3_backend
    http-request replace-path /s3(/)?(.*) /\2
    server versity 172.23.0.1:7070
EOF

```

### Step 6: Start the Services

Reload the systemd daemon so the Quadlet generator processes the files and registers the automatic starts.

```bash
sudo systemctl daemon-reload

for svc in postgres smd boot-service coredhcp openchami-haproxy; do
    sudo systemctl enable --now $svc.service
done

sudo podman ps

```

### Step 7: Build & Upload the Boot Image to VersityGW

Generate the SquashFS image and upload the artifacts to the S3 bucket using the auto-generated root credentials.

```bash
# Generate the SquashFS image from a pre-staged SLES rootfs
sudo mksquashfs /mnt/sles_root /data/boot-images/sles15-compute.squashfs -comp xz

# Copy kernel and initrd
sudo cp /mnt/sles_root/boot/vmlinuz /data/boot-images/
sudo cp /mnt/sles_root/boot/initrd /data/boot-images/

# Source the auto-generated root credentials
source /etc/versitygw/secrets.env

# Configure AWS CLI
aws configure set aws_access_key_id $ROOT_ACCESS_KEY
aws configure set aws_secret_access_key $ROOT_SECRET_KEY
aws configure set region us-east-1

# Create bucket and upload
aws --endpoint-url http://172.23.0.1:7070 s3 mb s3://boot-images
aws --endpoint-url http://172.23.0.1:7070 s3 cp /data/boot-images/sles15-compute.squashfs s3://boot-images/
aws --endpoint-url http://172.23.0.1:7070 s3 cp /data/boot-images/vmlinuz s3://boot-images/
aws --endpoint-url http://172.23.0.1:7070 s3 cp /data/boot-images/initrd s3://boot-images/

```

### Step 8: Populate Inventory & Boot-Service Parameters

Register the compute node's MAC address in SMD and set its boot arguments via the Boot-Service API. Notice the S3 URLs point to port `7070`.

```bash
# Register Ethernet Interface
curl -X POST http://172.23.0.1:27779/hsm/v2/Inventory/EthernetInterfaces \
  -H "Content-Type: application/json" \
  -d '{
    "ID": "'$COMPUTE_MAC'",
    "Description": "Forge Compute Node NIC",
    "MACAddress": "'$COMPUTE_MAC'",
    "IPAddresses": [{"IPAddress": "172.24.1.10"}],
    "ComponentID": "x1000c0s1b0"
  }'

# Register Boot Parameters
curl -X POST http://172.23.0.1:27777/bss/boot/v1/bootparameters \
  -H "Content-Type: application/json" \
  -d '{
    "hosts": ["x1000c0s1b0"],
    "macs": ["'$COMPUTE_MAC'"],
    "params": "console=ttyS0,115200 root=live:http://172.23.0.1:7070/boot-images/sles15-compute.squashfs rd.live.image rd.neednet=1 ip=dhcp",
    "kernel": "http://172.23.0.1:7070/boot-images/vmlinuz",
    "initrd": "http://172.23.0.1:7070/boot-images/initrd"
  }'

```

### Step 9: Boot the Compute Node

Set the node to PXE boot and issue a power cycle.

```bash
curl -k -u ADMIN:PASSWORD -X PATCH https://172.24.0.3/redfish/v1/Systems/1 \
  -H "Content-Type: application/json" \
  -d '{"Boot": {"BootSourceOverrideTarget": "Pxe", "BootSourceOverrideEnabled": "Once"}}'

curl -k -u ADMIN:PASSWORD -X POST https://172.24.0.3/redfish/v1/Systems/1/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "On"}'

```