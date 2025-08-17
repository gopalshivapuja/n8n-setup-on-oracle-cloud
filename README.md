# Self-Hosted n8n on Oracle Cloud Free Tier with Podman and Caddy

This guide provides step-by-step instructions on how to set up n8n, a powerful workflow automation tool, on an Oracle Cloud Infrastructure (OCI) Free Tier instance. We will be using Podman for container management and Caddy as a reverse proxy for secure access with automatic SSL/TLS.

## Table of Contents

1.  [Introduction](#introduction)
2.  [Prerequisites](#prerequisites)
3.  [Oracle Cloud Setup](#oracle-cloud-setup)
    *   [Create an Oracle Cloud Account](#create-an-oracle-cloud-account)
    *   [Create a Compute Instance](#create-a-compute-instance)
    *   [Configure Virtual Cloud Network (VCN) Security Lists](#configure-virtual-cloud-network-vcn-security-lists)
4.  [Instance Configuration](#instance-configuration)
5.  [n8n and Caddy Setup](#n8n-and-caddy-setup)
6.  [Post-Setup and Access](#post-setup-and-access)
7.  [Troubleshooting and Tips](#troubleshooting-and-tips)

## 1. Introduction

n8n is an extendable workflow automation tool that helps you connect anything to everything. With its self-hosted option, you gain full control over your data and workflows. This guide focuses on deploying n8n on Oracle Cloud's Free Tier, leveraging Podman (which is default on Oracle Linux) and Caddy for a robust, secure, and easily maintainable setup.

## 2. Prerequisites

Before you begin, ensure you have:

*   An Oracle Cloud Infrastructure (OCI) Free Tier account.
*   Basic understanding of Linux command-line operations.
*   An SSH client (e.g., OpenSSH, PuTTY).
*   (Optional but recommended) A registered domain name for easier access and Caddy's automatic SSL/TLS.

## 3. Oracle Cloud Setup

### Create an Oracle Cloud Account

If you don't already have one, sign up for an Oracle Cloud Free Tier account. This will provide you with a perpetual free tier instance suitable for running n8n.

### Create a Compute Instance

1.  Log in to your Oracle Cloud Console.
2.  Navigate to **Compute** > **Instances**.
3.  Click **Create Instance**.
4.  **Name**: Give your instance a descriptive name (e.g., `n8n-arm-server`).
5.  **Operating System or Image Source**: Select an "Always Free-eligible" image such as `Oracle Linux 8` or `Oracle Linux 9` (both come with Podman pre-installed and are free tier eligible for Arm).
6.  **Placement**: Choose an Availability Domain. For free tier, you'll typically be limited to one.
7.  **Shape**: Select "Ampere" as the "Instance Shape" and choose the "VM.Standard.A1.Flex" shape. You can allocate up to **4 OCPUs** and **24 GB of memory** as part of the Always Free tier.
    *   **Always Free Note**: Oracle Cloud provides 3,000 OCPU hours and 18,000 GB hours per month for free, which typically allows for a configuration of 4 OCPUs and 24 GB of memory for an Arm-based instance.
8.  **Networking**: Ensure "Create new virtual cloud network" and "Create new public subnet" are selected if you don't have an existing VCN. Make note of your VCN and subnet names.
9.  **Add SSH keys**: Generate a new SSH key pair or upload your existing public key. **Save the private key securely** as you will need it to connect to your instance.
10. **Boot Volume**: The default 50 GB should be sufficient for the OS and n8n, but you can increase it to 200 GB for more storage, which is also free tier eligible.
11. Click **Create**.

Wait for the instance to provision and show a "Running" state.

You can also create the instance using the OCI CLI. Ensure the OCI CLI is installed and configured on your local machine, then use the following command (replace placeholders):

```bash
oci compute instance launch \
  --compartment-id <compartment_ocid> \
  --availability-domain <availability_domain> \
  --shape VM.Standard.A1.Flex \
  --shape-config '{\"ocpus\": 4, \"memoryInGBs\": 24}' \
  --image-id <image_ocid> \
  --subnet-id <subnet_ocid> \
  --assign-public-ip true \
  --ssh-authorized-keys-file <path_to_public_ssh_key>
```
For detailed CLI usage, refer to the [OCI CLI Command Reference](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/).

### Configure Virtual Cloud Network (VCN) Security Lists

To allow external access to n8n (port 5678) and Caddy (ports 80 and 443 for HTTP/HTTPS), you need to add ingress rules to your VCN's security list.

1.  From your running instance details page, click on the **Subnet** link under "Virtual Cloud Network".
2.  On the Subnet details page, click on the **Default Security List** (or the security list associated with your subnet).
3.  Click **Add Ingress Rules**.
4.  Add the following rules:

    *   **Rule 1 (HTTP - Caddy)**:
        *   **Source Type**: CIDR
        *   **Source CIDR**: `0.0.0.0/0` (Allows access from any IP address)
        *   **IP Protocol**: TCP
        *   **Destination Port Range**: `80`
        *   **Description**: `Allow HTTP for Caddy`

    *   **Rule 2 (HTTPS - Caddy)**:
        *   **Source Type**: CIDR
        *   **Source CIDR**: `0.0.0.0/0`
        *   **IP Protocol**: TCP
        *   **Destination Port Range**: `443`
        *   **Description**: `Allow HTTPS for Caddy`

    *   **Rule 3 (n8n - for direct access/troubleshooting if needed)**:
        *   **Source Type**: CIDR
        *   **Source CIDR**: `0.0.0.0/0`
        *   **IP Protocol**: TCP
        *   **Destination Port Range**: `5678`
        *   **Description**: `Allow n8n access`

    *   **Rule 4 (SSH - if not already present)**:
        *   **Source Type**: CIDR
        *   **Source CIDR**: `0.0.0.0/0`
        *   **IP Protocol**: TCP
        *   **Destination Port Range**: `22`
        *   **Description**: `Allow SSH access`

5.  Click **Add Ingress Rules**.

## 4. Instance Configuration

1.  **Connect to your instance via SSH**:

    Open your terminal or SSH client and use the private key you saved earlier:

    ```bash
    ssh -i <path_to_your_private_key> opc@<your_instance_public_ip>
    ```

    Replace `<path_to_your_private_key>` with the actual path to your `.oci` file and `<your_instance_public_ip>` with the public IP address of your Oracle Cloud instance.

2.  **Update the system**:

    It's good practice to update your system's packages.

    ```bash
    sudo dnf update -y
    ```

3.  **Install `git` (if not already installed)**:

    ```bash
    sudo dnf install git -y
    ```

4.  **Podman (Pre-installed on Oracle Linux)**:

    Oracle Linux typically comes with Podman pre-installed. You can verify its version:

    ```bash
    podman --version
    ```

    If `podman-compose` or `docker compose` is not found, you might need to install `podman-docker` for compatibility:

    ```bash
    sudo dnf install podman-docker -y
    ```

5.  **Configure FirewallD**:

    Oracle Linux uses FirewallD. You need to open ports for n8n and Caddy.

    ```bash
    sudo firewall-cmd --permanent --add-service=http
    sudo firewall-cmd --permanent --add-service=https
    sudo firewall-cmd --permanent --add-port=5678/tcp
    sudo firewall-cmd --reload
    sudo firewall-cmd --list-all
    ```

    Verify that `http`, `https`, and `5678/tcp` are listed under `ports` or `services`.

## 5. n8n and Caddy Setup

1.  **Clone the repository**:

    On your Oracle Linux instance, clone the GitHub repository where this `README.md` resides (or create the directory structure manually). Let's assume you've structured your project similar to this guide, with a `n8n-setup` directory.

    ```bash
    git clone <your-github-repo-url>
    cd <your-github-repo-name>/n8n-setup # Or wherever you want to place these files
    ```

    Alternatively, you can create the directories manually:

    ```bash
    mkdir -p n8n-setup/caddy/data n8n-setup/caddy/config n8n-setup/n8n/data
    cd n8n-setup
    ```

2.  **Create `docker-compose.yml`**:

    Create a file named `docker-compose.yml` inside your `n8n-setup` directory with the following content:

    ```yaml
version: '3.8'
services:
  caddy:
    image: docker.io/caddy:2
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile:ro,Z
      - ./caddy/data:/data:Z
      - ./caddy/config:/config:Z
    networks: [web]

  n8n:
    image: docker.io/n8nio/n8n:1.106.3
    container_name: n8n
    restart: unless-stopped
    environment:
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - WEBHOOK_URL=${WEBHOOK_URL}
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
    volumes:
      - ./n8n/data:/home/node/.n8n:Z,U
    networks: [web]

networks:
  web:
    driver: bridge
    ```

3.  **Create `caddy/Caddyfile`**:

    Create a directory `caddy` inside `n8n-setup`, and then create a file named `Caddyfile` inside the `caddy` directory with the following content. **Replace `your_domain.com` with your actual domain name.**

    ```caddyfile
your_domain.com {
  encode zstd gzip
  reverse_proxy n8n:5678
}
    ```

4.  **Create `.env` file**:

    Create a file named `.env` in the `n8n-setup` directory. This file will hold your environment variables. **Replace `your_domain.com` with your actual domain, and set your desired timezone.**

    ```ini
N8N_HOST=your_domain.com
WEBHOOK_URL=https://your_domain.com/
N8N_EDITOR_BASE_URL=https://your_domain.com/
GENERIC_TIMEZONE=Asia/Kolkata # Example: Europe/Berlin, America/New_York
    ```

5.  **DNS Configuration (Important!)**:

    Before starting the services, ensure your domain's A record points to the public IP address of your Oracle Cloud instance. This is crucial for Caddy to automatically provision SSL/TLS certificates.

6.  **Start n8n and Caddy**:

    From the `n8n-setup` directory, run the following command to start your services. Oracle Linux uses Podman, so `podman-compose` is the preferred command.

    ```bash
    podman-compose up -d
    # If podman-compose is not found, try:
    # docker compose up -d
    ```

    The `-d` flag runs the containers in detached mode (in the background).

7.  **Verify container status**:

    Check if the containers are running:

    ```bash
    podman ps -a
    # Or
    # docker ps -a
    ```

    You should see `n8n` and `caddy` containers in the "Up" state.

## 6. Post-Setup and Access

1.  **Access n8n**:

    Open your web browser and navigate to `https://your_domain.com` (replace `your_domain.com` with the domain you configured). Caddy will automatically handle the SSL/TLS certificate provisioning, so it might take a minute or two for the HTTPS to become active on the first run.

2.  **Initial n8n Setup**:

    The first time you access n8n, you will be prompted to create an owner account. Follow the on-screen instructions to complete the setup.

3.  **Explore n8n**:

    Once logged in, you can start creating your workflows, connecting to various services, and automating tasks.

## 7. Troubleshooting and Tips

*   **Firewall Issues**: If you cannot access n8n or Caddy, double-check your Oracle Cloud VCN security list ingress rules and your instance's FirewallD settings.
*   **Domain Not Resolving**: Ensure your domain's A record points to your Oracle Cloud instance's public IP address.
*   **Caddy SSL/TLS Issues**: Check Caddy's logs for errors if SSL/TLS isn't working. You can view logs with `podman logs caddy` or `docker logs caddy`.
*   **n8n Container Issues**: If n8n isn't starting or behaving as expected, check its logs with `podman logs n8n` or `docker logs n8n`.
*   **Updating n8n and Caddy**: To update your containers to the latest versions, navigate to the `n8n-setup` directory and run:

    ```bash
    podman-compose pull
    podman-compose up -d
    # Or if using docker compose:
    # docker compose pull
    # docker compose up -d
    ```

*   **Persistent Data**: All your n8n workflows and data are stored in the `./n8n/data` directory on your host machine, and Caddy's configuration and SSL certificates are in `./caddy/data` and `./caddy/config`. This means your data will persist even if you stop or remove the containers.
*   **Backup**: Regularly back up your `n8n-setup` directory, especially the `n8n/data` and `caddy/data` folders.
