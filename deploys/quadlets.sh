#!/bin/bash
# deploy_openchami_island.sh

dnf install -y podman jq

mkdir -p /etc/containers/systemd/

# 1. Create the shared container network
cat <<EOF > /etc/containers/systemd/openchami.network
[Network]
NetworkName=openchami
EOF

# 2. Create the Database Dependency (PostgreSQL)
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

# 3. Create TokenSmith (Authentication)
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

# 4. Create State Management Database (SMD)
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

# 5. Create Power Control Service (PCS)
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

# 6. Create Boot Service (Modern BSS replacement)
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

# 7. Create Metadata Service (Modern Cloud-Init replacement)
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

# 8. Reload systemd and start services
systemctl daemon-reload
systemctl enable --now ochami-postgres.service
systemctl enable --now ochami-tokensmith.service
systemctl enable --now ochami-smd.service
systemctl enable --now ochami-pcs.service
systemctl enable --now ochami-boot-service.service
systemctl enable --now ochami-metadata-service.service
