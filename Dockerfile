FROM odoo:18.0-20251008

USER root

# Install needed deps
RUN apt-get update && apt-get install -y git postgresql-client gosu && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /mnt/enterprise /mnt/extra-addons

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --break-system-packages -r /tmp/requirements.txt

USER odoo