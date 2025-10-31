#!/bin/bash
set -e

# CARGAR VARIABLES
: ${DB_HOST:=postgres}
: ${DB_PORT:=5432}
: ${POSTGRES_USER:=odoo}
: ${POSTGRES_PASSWORD:=}
: ${POSTGRES_DB:=odoo}
: ${ODOO_ADMIN_PASSWORD:=admin}
: ${DEMO:=False}

# Validaciones
[ -z "$POSTGRES_PASSWORD" ] && { echo "ERROR: POSTGRES_PASSWORD requerida"; exit 1; }
[ -z "$ODOO_ADMIN_PASSWORD" ] && { echo "ERROR: ODOO_ADMIN_PASSWORD requerida"; exit 1; }

ODOO_RC="/etc/odoo/odoo.conf"

# Generar config
sed "s/{{ODOO_ADMIN_PASSWORD}}/$ODOO_ADMIN_PASSWORD/g" \
    /etc/odoo/odoo.conf.template > "$ODOO_RC"

# Esperar PostgreSQL
echo "Esperando PostgreSQL..."
while ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$POSTGRES_USER" > /dev/null 2>&1; do sleep 1; done

export PGPASSWORD="$POSTGRES_PASSWORD"

# Crear base si no existe
DB_EXISTS=$(psql -h "$DB_HOST" -U "$POSTGRES_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$POSTGRES_DB'")
if [ "$DB_EXISTS" != "1" ]; then
    echo "Creando base de datos: $POSTGRES_DB"
    psql -h "$DB_HOST" -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE \"$POSTGRES_DB\""
else
    echo "Base '$POSTGRES_DB' ya existe."
fi

# Dar permisos completos
psql -h "$DB_HOST" -U "$POSTGRES_USER" -d postgres -c "ALTER USER \"$POSTGRES_USER\" WITH SUPERUSER;"

# Inicializar Odoo
BASE_INSTALLED=$(psql -h "$DB_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
    "SELECT 1 FROM ir_module_module WHERE name='base' AND state='installed'" 2>/dev/null || echo "0")

if [ "$BASE_INSTALLED" != "1" ]; then
    echo "Instalando módulo base..."
    INIT_CMD="odoo --init base"
    if [ "$DEMO" = "True" ] || [ "$DEMO" = "true" ]; then
        INIT_CMD="$INIT_CMD --load-demo-data"
        echo "Cargando datos de demo..."
    else
        echo "DEMO=False → sin datos de prueba"
    fi
    $INIT_CMD \
        --database="$POSTGRES_DB" \
        --db_host="$DB_HOST" \
        --db_port="$DB_PORT" \
        --db_user="$POSTGRES_USER" \
        --db_password="$POSTGRES_PASSWORD" \
        --stop-after-init
else
    echo "Odoo ya inicializado."
fi

# Iniciar servidor
exec odoo \
    --database="$POSTGRES_DB" \
    --db_host="$DB_HOST" \
    --db_port="$DB_PORT" \
    --db_user="$POSTGRES_USER" \
    --db_password="$POSTGRES_PASSWORD" \
    --http-interface=0.0.0.0 \
    --http-port=8069 \
    --proxy-mode