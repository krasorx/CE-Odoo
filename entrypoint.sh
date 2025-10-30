#!/bin/bash

set -e

# Set the postgres database host, port, user, and password from environment variables
: ${DB_HOST:='postgres'}
: ${DB_PORT:=5432}
: ${DB_USER:='odoo'}
: ${DB_PASSWORD:='odoo'}

# Path to the Odoo configuration file
ODOO_RC="/etc/odoo/odoo.conf"

# Function to check if a parameter exists in the config file and use it if present
DB_ARGS=()
function check_config() {
    param="$1"
    value="$2"
    if grep -q -E "^\s*\b${param}\b\s*=" "$ODOO_RC" ; then       
        value=$(grep -E "^\s*\b${param}\b\s*=" "$ODOO_RC" | cut -d " " -f3 | sed 's/["\n\r]//g')
    fi
    DB_ARGS+=("--${param}")
    DB_ARGS+=("${value}")
}

# Check and set database parameters
check_config "db_host" "$DB_HOST"
check_config "db_port" "$DB_PORT"
check_config "db_user" "$DB_USER"
check_config "db_password" "$DB_PASSWORD"

sed "s/{{ODOO_ADMIN_PASSWORD}}/$ODOO_ADMIN_PASSWORD/g" /etc/odoo/odoo.conf.template > "$ODOO_RC"

echo "DB_HOST=$DB_HOST DB_PORT=$DB_PORT DB_USER=$DB_USER DB_PASSWORD=$DB_PASSWORD" > /tmp/debug.log

# Wait for PostgreSQL to be ready
sleep 10

# Initialize Odoo database
echo "Initializing Odoo database..."
odoo --init base \
  --db_host="$DB_HOST" \
  --db_port="$DB_PORT" \
  --db_user="$DB_USER" \
  --db_password="$DB_PASSWORD" \
  --stop-after-init

# Start Odoo with proxy mode and bind to all interfaces
echo "Starting Odoo server..."
exec odoo \
  --db_host="$DB_HOST" \
  --db_port="$DB_PORT" \
  --db_user="$DB_USER" \
  --db_password="$DB_PASSWORD" \
  --http-interface=0.0.0.0 \
  --http-port=8069 \
  --proxy-mode