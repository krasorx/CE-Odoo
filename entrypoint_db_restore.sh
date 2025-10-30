#!/bin/bash
set -e

# --- Environment Variables with Defaults ---
: ${DB_HOST:='postgres'}
: ${DB_PORT:=5432}
: ${DB_USER:='odoo'}
: ${DB_PASSWORD:='odoo'}
: ${POSTGRES_DB:='odoo'}
: ${BACKUP_NAME:=''}
: ${ODOO_ADMIN_PASSWORD:=''}

echo "=== Entrypoint Starting ==="
echo "Env: DB_HOST=$DB_HOST, DB_PORT=$DB_PORT, DB_USER=$DB_USER, POSTGRES_DB=$POSTGRES_DB, BACKUP_NAME=$BACKUP_NAME"

# --- Odoo config file paths ---
ODOO_CONF_TEMPLATE="/etc/odoo/odoo.conf.template"
ODOO_CONF="/etc/odoo/odoo.conf"

# --- Generate Odoo config from template ---
if [ -z "$ODOO_ADMIN_PASSWORD" ]; then
    echo "ERROR: ODOO_ADMIN_PASSWORD is required!"
    exit 1
fi
sed "s/{{ODOO_ADMIN_PASSWORD}}/$ODOO_ADMIN_PASSWORD/g" "$ODOO_CONF_TEMPLATE" > "$ODOO_CONF"
echo "Odoo config generated: $ODOO_CONF"

# --- Wait for PostgreSQL to be ready ---
echo "Waiting for PostgreSQL server..."
until PGPASSWORD="$DB_PASSWORD" pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" >/dev/null 2>&1; do
    echo "PostgreSQL server unavailable - sleeping 2s..."
    sleep 2
done
echo "PostgreSQL server ready!"

# --- Check if database exists ---
DB_EXISTS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -tAc "SELECT 1 FROM pg_database WHERE datname='$POSTGRES_DB'")

# --- Check if database has tables (is properly initialized) ---
DB_HAS_TABLES=0
if [ "$DB_EXISTS" = "1" ]; then
    DB_HAS_TABLES=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$POSTGRES_DB" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'" 2>/dev/null || echo "0")
    echo "Database exists with $DB_HAS_TABLES tables"
fi

# --- Restore from backup or init ---
if [ -n "$BACKUP_NAME" ] && [ -f "/backup/$BACKUP_NAME" ]; then
    if [ "$DB_EXISTS" = "1" ] && [ "$DB_HAS_TABLES" -gt "0" ]; then
        echo "Database $POSTGRES_DB already exists and has data - skipping restore."
    else
        if [ "$DB_EXISTS" = "1" ]; then
            echo "Database $POSTGRES_DB exists but is empty - dropping and recreating..."
            PGPASSWORD="$DB_PASSWORD" dropdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$POSTGRES_DB"
        fi
        
        echo "Creating database $POSTGRES_DB..."
        PGPASSWORD="$DB_PASSWORD" createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$POSTGRES_DB"
        
        echo "Restoring /backup/$BACKUP_NAME into $POSTGRES_DB..."
        
        if [[ "$BACKUP_NAME" == *.dump ]]; then
            PGPASSWORD="$DB_PASSWORD" pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$POSTGRES_DB" --verbose --no-owner --no-privileges "/backup/$BACKUP_NAME" 2>&1 | grep -v "^pg_restore: warning:" || true
        else
            PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$POSTGRES_DB" -f "/backup/$BACKUP_NAME"
        fi
        echo "Database restoration complete."
        
        # Restore filestore
        FILESTORE_SRC="/backup/filestore"
        FILESTORE_DST="/var/lib/odoo/filestore/$POSTGRES_DB"
        echo "Checking filestore source directory contents:"
        ls -l "$FILESTORE_SRC"
        if [ -d "$FILESTORE_SRC" ]; then
            echo "Restoring filestore from $FILESTORE_SRC to $FILESTORE_DST..."
            rm -rf "$FILESTORE_DST"
            mkdir -p "$FILESTORE_DST"
            cp -r "$FILESTORE_SRC/"* "$FILESTORE_DST/" || echo "WARNING: Failed to copy filestore contents"
            chown -R odoo:odoo "$FILESTORE_DST"
            echo "Filestore restoration complete."
        else
            echo "No filestore found at $FILESTORE_SRC - creating empty directory..."
            mkdir -p "$FILESTORE_DST"
            chown -R odoo:odoo "$FILESTORE_DST"
        fi
    fi
else
    if [ "$DB_EXISTS" != "1" ] || [ "$DB_HAS_TABLES" -eq "0" ]; then
        echo "No backup found - initializing new database $POSTGRES_DB..."
        if [ "$DB_EXISTS" = "1" ]; then
            echo "Dropping empty database..."
            PGPASSWORD="$DB_PASSWORD" dropdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$POSTGRES_DB"
        fi
        
        echo "Creating database without initializing modules..."
        odoo --database="$POSTGRES_DB" \
             --db_host="$DB_HOST" \
             --db_port="$DB_PORT" \
             --db_user="$DB_USER" \
             --db_password="$DB_PASSWORD" \
             --addons-path=/usr/lib/python3/dist-packages/odoo/addons,/mnt/enterprise \
             --stop-after-init \
             --without-demo=all
        echo "Database created. Modules can be installed through the UI."
    else
        echo "Database $POSTGRES_DB already exists with data - skipping initialization."
    fi
fi

# --- Start Odoo server ---
echo "Starting Odoo server on port 8069..."
exec odoo \
    --database="$POSTGRES_DB" \
    --db_host="$DB_HOST" \
    --db_port="$DB_PORT" \
    --db_user="$DB_USER" \
    --db_password="$DB_PASSWORD" \
    --addons-path=/usr/lib/python3/dist-packages/odoo/addons,/mnt/enterprise \
    --http-interface=0.0.0.0 \
    --http-port=8069 \