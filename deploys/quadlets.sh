#!/bin/bash
# deploy_openchami_island.sh

echo "[1/4] Detecting OS and installing prerequisites..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|debian) apt-get update && apt-get install -y podman jq ;;
        fedora|rhel|centos|rocky|almalinux) dnf install -y podman jq ;;
        opensuse*|sles) zypper install -y podman jq ;;
        alpine) apk add podman jq ;;
        arch) pacman -Sy --noconfirm podman jq ;;
        sles|suse) zypper install -y podman jq ;;
        *) 
            echo "Unrecognized OS: $ID. Attempting to proceed assuming podman and jq are already installed." 
            ;;
    esac
else
    echo "Could not read /etc/os-release. Attempting to proceed assuming podman and jq are already installed."
fi

echo "[2/4] Generating systemd Quadlet configuration files..."
mkdir -p /etc/containers/systemd/

cat <<EOF > /etc/containers/systemd/openchami.network
[Network]
NetworkName=openchami
EOF

cat <<EOF > /etc/containers/systemd/ochami-postgres.container
[Unit]
Description=OpenCHAMI PostgreSQL Database

[Container]
Image=docker.io/postgres:15-alpine
Network=openchami.network
Environment=POSTGRES_USER=admin
Environment=POSTGRES_PASSWORD=openchami_db_pass
Environment=POSTGRES_DB=openchami
Volume=ochami-pgdata:/var/lib/postgresql/data

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/containers/systemd/ochami-tokensmith.container
[Unit]
Description=OpenCHAMI TokenSmith (Auth)
After=ochami-postgres.service

[Container]
Image=ghcr.io/openchami/tokensmith:latest
Network=openchami.network
PublishPort=8080:8080
Environment=DB_URI=postgres://admin:openchami_db_pass@ochami-postgres:5432/openchami?sslmode=disable

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/containers/systemd/ochami-smd.container
[Unit]
Description=OpenCHAMI SMD
After=ochami-tokensmith.service

[Container]
Image=ghcr.io/openchami/smd:latest
Network=openchami.network
PublishPort=27779:27779
Environment=POSTGRES_HOST=ochami-postgres
Environment=POSTGRES_PORT=5432
Environment=POSTGRES_USER=admin
Environment=POSTGRES_PASSWORD=openchami_db_pass
Environment=POSTGRES_DB=openchami

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/containers/systemd/ochami-pcs.container
[Unit]
Description=OpenCHAMI PCS
After=ochami-tokensmith.service

[Container]
Image=ghcr.io/openchami/pcs:latest
Network=openchami.network
PublishPort=28000:28000

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/containers/systemd/ochami-boot-service.container
[Unit]
Description=OpenCHAMI Boot Service
After=ochami-smd.service ochami-tokensmith.service

[Container]
Image=ghcr.io/openchami/boot-service:latest
Network=openchami.network
PublishPort=27778:27778
Exec=serve --port 27778 --enable-auth --hsm-url http://ochami-smd:27779 --tokensmith_url http://ochami-tokensmith:8080

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/containers/systemd/ochami-metadata-service.container
[Unit]
Description=OpenCHAMI Metadata Service
After=ochami-smd.service ochami-tokensmith.service

[Container]
Image=ghcr.io/openchami/metadata-service:latest
Network=openchami.network
PublishPort=8888:8888
Environment=SMD_URL=http://ochami-smd:27779
Environment=TOKENSMITH_URL=http://ochami-tokensmith:8080
Exec=serve --port 8888

[Install]
WantedBy=multi-user.target
EOF

echo "[3/4] Pre-pulling container images to display progress..."
IMAGES=(
    "docker.io/postgres:15-alpine"
    "ghcr.io/openchami/tokensmith:latest"
    "ghcr.io/openchami/smd:latest"
    "ghcr.io/openchami/pcs:latest"
    "ghcr.io/openchami/boot-service:latest"
    "ghcr.io/openchami/metadata-service:latest"
)

for image in "${IMAGES[@]}"; do
    echo "Pulling $image..."
    podman pull "$image"
done

echo "[4/4] Reloading systemd and starting services..."
systemctl daemon-reload

SERVICES=(
    "ochami-postgres.service"
    "ochami-tokensmith.service"
    "ochami-smd.service"
    "ochami-pcs.service"
    "ochami-boot-service.service"
    "ochami-metadata-service.service"
)

for service in "${SERVICES[@]}"; do
    echo "Starting $service..."
    systemctl start "$service"
done

echo "OpenCHAMI deployment script finished."
