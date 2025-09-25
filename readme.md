# Dirty and cursed FastAPI server deployment scripts
A script for quickly deploying FastAPI applications to Linux servers using Gunicorn, Supervisor, and Nginx. This is just something for my personal use for quick and dirty work. If you're looking into building kubernetes, don't.

## Features

- **Dirty FastAPI deployment** with Gunicorn ASGI server 
- **Process management** using Supervisor for automatic restarts
- **Reverse proxy setup** with Nginx configuration
- **SSL/TLS** with automatic Let's Encrypt certificate setup
- **Log management** with automatic backup and rotation
- **Rsync-based synchronization** with a plain old txt file for exlusions
- **One-command deployment** from local machine to remote server

## Prerequisites

### Local Machine
Developed using MacOS / Unix
- `zshell` shell
- `rsync` installed
- SSH access to your target server

### Remote Server (Linux)
- Ubuntu/Debian-based system
- `sudo` privileges without a password (There is a better way I know)
- SSH server running
- Python 3.x installed

## Setup

### 1. Clone and Configure 

```bash
cd <your_fastapi_app_root>
git clone <repository-url> ./deployment 
mv ./deployment/deployment/* ./deployment 
cd deployment
```
### 2. Create Environment Configuration

Copy the example environment file and configure it:

```bash
cp deployment/.env.deployment.example deployment/.env.deployment
```

Edit `deployment/.env.deployment` with your server details:

```bash
HostNameForNginx=your-domain.com
HostName=your.server.ip.address
SshUser=your_username
AddKeysToAgent=yes
UseKeychain=yes
IdentityFile=/path/to/your/private/key.pem
ProjectName=your_project_name
EmailContactForCertbot=your-email@example.com
```

### 3. Prepare Your FastAPI Application

Ensure your FastAPI application:
- Has a `main.py` file with an `app` variable (FastAPI instance)
- Includes a `requirements.txt` file with all dependencies
- Is structured as a standard Python project

## Deployment

### Quick Deploy

Run the main deployment script:

```bash
sh ./deployment/update_to_server.sh
```

This script will:
1. Generate necessary configuration files
2. Create Nginx, Gunicorn, and Supervisor configurations
3. Transfer files to the remote server
4. Execute the server-side setup script (restarts the server too)

### What Happens During Deployment

#### On Your Local Machine (`update_to_server.sh`):
- Generates dynamic Nginx configuration with SSL support
- Creates Supervisor configuration for process management
- Creates Gunicorn startup script
- Transfers all files to the server via rsync
- Triggers remote server setup

#### On the Remote Server (`update_on_server.sh`):
- Sets up Python virtual environment
- Installs/updates Python dependencies
- Configures SSL certificates with Let's Encrypt
- Updates Nginx configuration
- Updates Supervisor configuration
- Restarts services (Nginx, Supervisor, Gunicorn)

## File Structure

```
├── deployment/
│   ├── update_to_server.sh           # Main deployment script (run locally)
│   ├── rsync_exclude.txt             # Files to exclude from sync
│   └── .env.deployment.example       # Environment configuration template
├── main.py                           # Your FastAPI application
└── ...rest of your project
```

## Configuration Files
Basically this is just a templater. Configure further inside ``update_to_server.sh``

### Nginx Configuration
- Reverse proxy setup with Unix socket communication
- Cache disabled for development
- SSL/TLS support with automatic certificates
- Custom log file locations

### Gunicorn Configuration
- 4 worker processes (configurable)
- Unix socket binding
- logging

### Supervisor Configuration
- Automatic process restart on failure
- Separate log files for stdout and stderr

### SSL
- Automatic cert request via certbot, if certs already exist don't redo but instead collect existing ones and sed them back after updating

### Logs
- Everything should be in the root ``logs`` -folder

## Important Notes
- **Development Use**: These scripts are designed for quick prototyping and development deployments for my needs, don't expect them to suit yours
- **Security**: Review and harden everything to your standards
- **SSL Certificates**: Initial setup uses test certificates; modify for production, error prone and probably broken already
- **File Permissions**: Problems might arise when rsync host doesn't have permissions or if socket isn't accessable to www-data (nginx)



