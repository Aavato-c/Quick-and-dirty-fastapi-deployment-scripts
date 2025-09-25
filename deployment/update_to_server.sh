#!/bin/bash


source .env.deployment
ROOT_DIR=$(dirname "$0")/..
cd $ROOT_DIR || exit 1




# ==================================================================================================================
# Set paths and names
# ==================================================================================================================
PATH_TO_UPDATE_ON_SERVER_SCRIPT=./deployment/update_on_server.sh

BASENAME_GUNICORN_SUPERVISOR_CONF=api.gunicorn.supervisor.conf
PATH_TO_GUNICORN_SUPERVISOR_CONF=./deployment/$BASENAME_GUNICORN_SUPERVISOR_CONF

BASENAME_GUNICORN_START_SCRIPT=api_gunicorn_start.sh
PATH_TO_GUNICORN_START_SCRIPT=./deployment/$BASENAME_GUNICORN_START_SCRIPT

BASENAME_NGINX_CONF=api_nginx.conf
PATH_TO_NGINX_CONF=./deployment/$BASENAME_NGINX_CONF
SSL_SERVER_BLOCK_STRING=""


SSL_301_BASENAME=ssl_server_301_redirect_string.txt
SSL_301_REDIRECT_STRING_FILE=./deployment/$SSL_301_BASENAME
SSL_301_REDIRECT_STRING_FILE_ON_SERVER=/home/$SshUser/api/deployment/$SSL_301_BASENAME

SSL_SERVER_BLOCK_STRING_BASENAME=ssl_server_block_string.txt
SSL_SERVER_BLOCK_STRING_FILE=./deployment/$SSL_SERVER_BLOCK_STRING_BASENAME
SSL_SERVER_BLOCK_STRING_FILE_ON_SERVER=/home/$SshUser/api/deployment/$SSL_SERVER_BLOCK_STRING_BASENAME

GUNICORN_SERVICE_NAME=app_server_gunicorn
GUNICORN_SERVICE_NAME_SUPERVISOR=app_server_gunicorn_supervisor

# ==================================================================================================================
# Create nginx conf file
# ==================================================================================================================
cat << EOF > $PATH_TO_NGINX_CONF
upstream app_server_upstream {
    server unix:/opt/sockets/gunicorn_$GUNICORN_SERVICE_NAME.sock fail_timeout=3;
}

server {
    listen 80;
    server_name $HostNameForNginx;
    keepalive_timeout 5;
    client_max_body_size 4G;

    access_log /home/$SshUser/api/logs/nginx_access.log;
    error_log /home/$SshUser/api/logs/nginx_error.log;

    proxy_hide_header Access-Control-Allow-Origin;
    add_header Access-Control-Allow-Origin \$http_origin;
    
    # Disable cache
    add_header 'Cache-Control' 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0';


    location / {
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_redirect off;

        if (!-f \$request_filename) {
            proxy_pass http://app_server_upstream;
            break;
        }
    
    }

    # <SERVER_BLOCK_STRING>

}

# <SERVER_301_REDIRECT_STRING>

EOF

cat << EOF > $SSL_SERVER_BLOCK_STRING_FILE
    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/$HostNameForNginx/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/$HostNameForNginx/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
EOF


cat << EOF > $SSL_301_REDIRECT_STRING_FILE
server {
    if (\$host = $HostNameForNginx) {
        return 301 https://\$host\$request_uri;
    } # managed by Certbot


    listen 80;
    server_name $HostNameForNginx;
    return 404; # managed by Certbot
}
EOF

# ==================================================================================================================
# Create update_on_server.sh script
# ==================================================================================================================
cat << EOF > $PATH_TO_UPDATE_ON_SERVER_SCRIPT
#!/bin/bash

# ======================================================================================= Load environment variables
API_DIR=/home/$SshUser/api
HOME_DIR=/home/$SshUser
SourceDIR=\$HOME_DIR/.bashrc
if [ -f "\$SourceDIR" ]; then
    . "\$SourceDIR"
    echo "Sourced \$SourceDIR"
else
    echo "\$SourceDIR not found"
    exit 1
fi
cd \$API_DIR || exit 1
echo "Current dir: \$(pwd)"


# ======================================================================================= Backup and remove old logs
TIMESTAMP=\$(date +"%Y%m%d_%H%M%S")
sudo mkdir -p /home/$SshUser/api/logs/backup
sudo mkdir -p /home/$SshUser/api/logs/backup/$TIMESTAMP
echo "Backing up old log files to /home/$SshUser/api/logs/backup/$TIMESTAMP"
sudo mv /home/$SshUser/api/logs/*.log /home/$SshUser/api/logs/backup/$TIMESTAMP 2>/dev/null || echo "No log files to back up"



# ======================================================================================= Set up virtual environment and install packages
PPath=/home/linuxbrew/.linuxbrew/bin/python3
#sudo chown -R $SshUser:$SshUser \$API_DIR/venv
#sudo chown -R $SshUser:$SshUser \$API_DIR/venv/bin/activate
if [ ! -d "\$API_DIR/venv" ]; then
    echo "Creating virtual environment..."
    \$PPath -m venv venv
else
    echo "Virtual environment already exists."
fi
echo "Activating virtual environment..."
source \$API_DIR/venv/bin/activate
echo "Activated virtual environment"

python3 -m pip install -r requirements.txt
echo "Installed/Updated Python packages"




# ======================================================================================== Install certbot if not installed
# Check if certbot env exists
if [ ! -d "/opt/certbot" ]; then
    echo "Certbot not found, installing..."
    sudo apt update
    sudo apt install -y python3 python3-dev python3-venv libaugeas-dev gcc || { echo "Failed to install dependencies for certbot"; exit 1; }
    sudo python3 -m venv /opt/certbot || { echo "Failed to create virtual environment for certbot"; exit 1; }
    sudo /opt/certbot/bin/pip install --upgrade pip || { echo "Failed to upgrade pip in certbot venv"; exit 1; }
    sudo /opt/certbot/bin/pip install certbot certbot-nginx || { echo "Failed to install certbot"; exit 1; }
    echo "Certbot installed."
else
    echo "Certbot already installed."
fi

# ======================================================================================== Obtain or renew SSL certificates
# Check if certs already exist and insert server block if they do
echo "Checking if SSL certificates exist already"
PREVIOUS_EXISTS=false
sudo cp /etc/nginx/sites-enabled/$BASENAME_NGINX_CONF ./${BASENAME_NGINX_CONF}.temp || { echo "Failed to back up nginx conf file"; exit 1; }
if sudo grep -q "ssl_certificate" ./${BASENAME_NGINX_CONF}.temp; then
    echo "SSL certificates found in nginx conf file."
    PREVIOUS_EXISTS=true
fi
rm -f ./${BASENAME_NGINX_CONF}.temp
echo "Previous SSL cert existence: \$PREVIOUS_EXISTS"

if [ PREVIOUS_EXISTS==true ]; then
    echo "SSL certificates already exist."
    SSL_SERVER_BLOCK_STRING=\$(< $SSL_SERVER_BLOCK_STRING_FILE_ON_SERVER)
    SSL_301_REDIRECT_STRING=\$(< $SSL_301_REDIRECT_STRING_FILE_ON_SERVER)

    echo "Read SSL server block and 301 redirect from files: \$SSL_SERVER_BLOCK_STRING and \$SSL_301_REDIRECT_STRING"
    
    # Insert SSL_SERVER_BLOCK_STRING into nginx conf file
    # Replace <SERVER_301_REDIRECT_STRING> placeholder with actual SSL 301 redirect string
    sed -i "/# <SERVER_301_REDIRECT_STRING>/{
        r $SSL_301_REDIRECT_STRING_FILE_ON_SERVER
        d
    }" /home/$SshUser/api/deployment/$BASENAME_NGINX_CONF

    # Replace <SERVER_BLOCK_STRING> placeholder with actual SSL server block string
    sed -i "/# <SERVER_BLOCK_STRING>/{
        r $SSL_SERVER_BLOCK_STRING_FILE_ON_SERVER
        d
    }" /home/$SshUser/api/deployment/$BASENAME_NGINX_CONF
    # Inserted SSL_SERVER_BLOCK_STRING into nginx conf file
    echo "Inserted SSL server block and 301 redirect into nginx conf file before copying to /etc/nginx/sites-enabled/"
    SHOULD_INSTALL_CERTS=false
else
    echo "SSL certificates do not exist yet."
    SHOULD_INSTALL_CERTS=true
    # Remove the placeholder lines if certs do not exist
    sed -i "/# <SERVER_BLOCK_STRING>/c\\" $PATH_TO_NGINX_CONF
    sed -i "/# <SERVER_301_REDIRECT_STRING>/c\\" $PATH_TO_NGINX_CONF
    echo "Removed placeholder lines for SSL server block and 301 redirect from nginx conf file."
fi

echo "Early exit for testing purposes."
echo "Should install certs: \$SHOULD_INSTALL_CERTS"

# ======================================================================================= Obtain or renew SSL certificates
if [ \$SHOULD_INSTALL_CERTS == "true" ]; then
    DOMAIN=$HostNameForNginx
    EMAIL=$EmailContactForCertbot
    CERTBOT_CMD=/opt/certbot/bin/certbot
    echo "Installing or renewing SSL certificates for \$DOMAIN using email \$EMAIL"
    sudo \$CERTBOT_CMD --nginx \\
--domain \$DOMAIN \\
--email \$EMAIL \\
--agree-tos \\
--no-eff-email \\
--non-interactive \\
--redirect \\
--test-cert
else
    echo "Skipping SSL certificate installation/renewal as per configuration."
fi





# ======================================================================================== Ensure socket permissions and dir exist
if [ ! -d "/opt/sockets" ]; then
    echo "Creating /opt/sockets directory..."
    sudo mkdir -p /opt/sockets
else
    echo "/opt/sockets directory already exists."
fi

sudo chown $SshUser:$SshUser /opt/sockets && echo "Changed ownership of /opt/sockets to $SshUser:$SshUser"
sudo chmod 755 /opt/sockets && echo "Set permissions of /opt/sockets to 755"




# ======================================================================================= Update nginx config file
sudo rm -f /etc/nginx/sites-enabled/$BASENAME_NGINX_CONF
# Test if old file was removed
if [ ! -f /etc/nginx/sites-enabled/$BASENAME_NGINX_CONF ]; then
    echo "Old nginx conf file removed successfully."
else
    echo "Failed to remove old nginx conf file."
    exit 1
fi
echo "Removed old nginx conf file"
sudo cp /home/$SshUser/api/deployment/$BASENAME_NGINX_CONF /etc/nginx/sites-enabled/
# Test file was copied correctly
if [ -f /etc/nginx/sites-enabled/$BASENAME_NGINX_CONF ]; then
    echo "$BASENAME_NGINX_CONF copied successfully."
else
    echo "Failed to copy $BASENAME_NGINX_CONF."
    exit 1
fi
echo "Copied nginx conf file"
sudo nginx -t
# sudo systemctl reload nginx || { echo "Nginx config reload failed"; exit 1; }
# echo "Nginx config reloaded"
sudo systemctl restart nginx || { echo "Nginx restart failed"; exit 1; }
echo "Nginx restarted successfully"




# ======================================================================================= Update gunicorn systemd service file
sudo rm -f /etc/supervisor/conf.d/$BASENAME_GUNICORN_SUPERVISOR_CONF
sudo cp /home/$SshUser/api/deployment/$BASENAME_GUNICORN_SUPERVISOR_CONF /etc/supervisor/conf.d/$BASENAME_GUNICORN_SUPERVISOR_CONF
echo "Copied supervisor conf file"
sudo supervisorctl reread
sudo supervisorctl update
echo "Supervisor updated"

sudo chmod +x /home/$SshUser/api/deployment/$BASENAME_GUNICORN_START_SCRIPT
echo "Made $BASENAME_GUNICORN_START_SCRIPT executable"





# ======================================================================================= Restart the gunicorn service
sudo supervisorctl stop $GUNICORN_SERVICE_NAME_SUPERVISOR
echo "Stopped $GUNICORN_SERVICE_NAME_SUPERVISOR"
sudo supervisorctl start $GUNICORN_SERVICE_NAME_SUPERVISOR
echo "Started $GUNICORN_SERVICE_NAME_SUPERVISOR"
sudo supervisorctl status $GUNICORN_SERVICE_NAME_SUPERVISOR
EOF



# ==================================================================================================================
# Create supervisor conf file
# ==================================================================================================================
cat << EOF > $PATH_TO_GUNICORN_SUPERVISOR_CONF
[program:$GUNICORN_SERVICE_NAME_SUPERVISOR]
command=/home/$SshUser/api/deployment/$BASENAME_GUNICORN_START_SCRIPT
user=$SshUser
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/home/$SshUser/api/logs/$GUNICORN_SERVICE_NAME_SUPERVISOR.log
stderr_logfile=/home/$SshUser/api/logs/$GUNICORN_SERVICE_NAME_SUPERVISOR_error.log
EOF





# ==================================================================================================================
# Create supervisor start script 
# ==================================================================================================================
cat << EOF > $PATH_TO_GUNICORN_START_SCRIPT
#!/bin/bash

PNAME=$GUNICORN_SERVICE_NAME
DIR=/home/$SshUser/api
USER=$SshUser
GROUP=$SshUser
WORKERS=4
WORKER_CLASS=uvicorn.workers.UvicornWorker
VENV=\$DIR/venv/bin/activate
BIND=unix:/opt/sockets/gunicorn_$GUNICORN_SERVICE_NAME.sock
LOG_LEVEL=debug
LOG_FILE=/home/\$USER/api/logs/gunicorn.log

cd \$DIR
echo "Changed dir to \$DIR"
source \$VENV || { echo "Failed to activate virtualenv"; exit 1; }
echo "Activated virtualenv"

# If gunicorn not available, exit
command -v gunicorn >/dev/null 2>&1 || { echo >&2 "Gunicorn not installed. Aborting."; exit 1; }

exec gunicorn main:app \\
    --name \$PNAME \\
    --workers \$WORKERS \\
    --worker-class \$WORKER_CLASS \\
    --user=\$USER \\
    --group=\$GROUP \\
    --bind=\$BIND \\
    --log-level=\$LOG_LEVEL \\
    --log-file=\$LOG_FILE
EOF

chmod +x $PATH_TO_GUNICORN_START_SCRIPT






# ==================================================================================================================
# Create run and logs dir on server
# ==================================================================================================================
ssh "$SshUser@$HostName" "mkdir -p /home/$SshUser/api/run"
ssh "$SshUser@$HostName" "mkdir -p /home/$SshUser/api/logs"




# ==================================================================================================================
# Copy files to server
# ==================================================================================================================
echo "Copying update script to server..."
rsync -avp \
    --chmod=Du=rwx,Dgo=rx \
    ./deployment/update_on_server.sh \
     $SshUser@$HostName:/home/$SshUser/api

echo "Copying gunicorn start script to server..."
rsync -avp \
    --chmod=Du=rwx,Dgo=rx \
    $PATH_TO_GUNICORN_START_SCRIPT \
     $SshUser@$HostName:/home/$SshUser/api/deployment


echo "Copying gunicorn supervisor conf file to server..."
rsync -avp \
    --chmod=Du=rwx,Dgo=rx \
    $PATH_TO_GUNICORN_SUPERVISOR_CONF \
     $SshUser@$HostName:/home/$SshUser/api/deployment

echo "Copying nginx conf file to server..."
rsync -avp \
    --chmod=Du=rwx,Dgo=rx \
    $PATH_TO_NGINX_CONF \
     $SshUser@$HostName:/home/$SshUser/api/deployment

     




# ==================================================================================================================
# Transfer rest of the files to server
# ==================================================================================================================
# sudo chown -R $SshUser:$SshUser <folder on remote>
rsync -avp \
    --exclude-from='./deployment/rsync_exclude.txt' \
    ./ \
     $SshUser@$HostName:/home/$SshUser/api



# ==================================================================================================================
# Run update script on server
# ==================================================================================================================
ssh "$SshUser@$HostName" "bash '/home/$SshUser/api/update_on_server.sh'"