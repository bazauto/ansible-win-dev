# Base image
FROM python:3.12-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    sshpass \
    git \
    curl \
    iproute2 \
    iputils-ping \
    openssh-client \
    python3-venv \
    python3-pip \
    sudo \
    gnupg2 \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install Podman and enable user namespaces
RUN apt-get update && apt-get install -y podman

# Ensure Podman rootless directory exists (do this as root)
RUN mkdir -p /run/podman && chmod 777 /run/podman

# Add environment variables for Podman
ENV CONTAINER_HOST="unix:///run/podman/podman.sock"
ENV CONTAINER_STORAGE_DRIVER=vfs

# Create non-root user
RUN useradd -ms /bin/bash vscode \
    && echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to non-root user
USER vscode
WORKDIR /workspace

# Copy requirements and install Python deps
COPY requirements.txt .
RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt
