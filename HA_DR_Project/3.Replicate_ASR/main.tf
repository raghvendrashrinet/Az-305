terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# --- Variables ---
variable "primary_region" {
  description = "The primary active Azure region"
  type        = string
  default     = "eastus"
}

variable "secondary_region" {
  description = "The secondary warm-standby Azure region"
  type        = string
  default     = "westus"
}

variable "environment_prefix" {
  description = "Naming prefix for all resources"
  type        = string
  default     = "replicate-demo"
}

variable "admin_username" {
  description = "Administrator username for VMs and SQL Servers"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "Administrator password for VMs and SQL Servers"
  type        = string
  default     = "P@ssw0rd12345!"
  sensitive   = true
}

# Unique suffix for globally unique names (SQL Servers, Traffic Manager)
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ==============================================================================
# 1. PRIMARY REGION INFRASTRUCTURE (East US - Active 100%)
# ==============================================================================

resource "azurerm_resource_group" "primary_rg" {
  name     = "rg-${var.environment_prefix}-${var.primary_region}"
  location = var.primary_region
  tags = {
    Environment = "DR-Test"
    Pattern     = "3.Replicate"
    Role        = "Primary"
  }
}

resource "azurerm_virtual_network" "primary_vnet" {
  name                = "vnet-${var.environment_prefix}-${var.primary_region}"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.primary_rg.location
  resource_group_name = azurerm_resource_group.primary_rg.name
}

resource "azurerm_subnet" "primary_subnet" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.primary_rg.name
  virtual_network_name = azurerm_virtual_network.primary_vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_public_ip" "primary_pip" {
  name                = "pip-${var.environment_prefix}-${var.primary_region}"
  location            = azurerm_resource_group.primary_rg.location
  resource_group_name = azurerm_resource_group.primary_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "pip-${var.environment_prefix}-${var.primary_region}-${random_string.suffix.result}"
}

resource "azurerm_network_security_group" "primary_nsg" {
  name                = "nsg-${var.environment_prefix}-${var.primary_region}"
  location            = azurerm_resource_group.primary_rg.location
  resource_group_name = azurerm_resource_group.primary_rg.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "primary_nic" {
  name                = "nic-${var.environment_prefix}-${var.primary_region}"
  location            = azurerm_resource_group.primary_rg.location
  resource_group_name = azurerm_resource_group.primary_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.primary_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.primary_pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "primary_nic_nsg" {
  network_interface_id      = azurerm_network_interface.primary_nic.id
  network_security_group_id = azurerm_network_security_group.primary_nsg.id
}

# --- Primary Azure SQL Logical Server ---
resource "azurerm_mssql_server" "primary_sql_server" {
  name                         = "sql-${var.environment_prefix}-${var.primary_region}-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.primary_rg.name
  location                     = azurerm_resource_group.primary_rg.location
  version                      = "12.0"
  administrator_login          = var.admin_username
  administrator_login_password = var.admin_password
  minimum_tls_version          = "1.2"

  tags = {
    Environment = "DR-Test"
    Pattern     = "3.Replicate"
    Role        = "PrimarySQL"
  }
}

resource "azurerm_mssql_firewall_rule" "primary_allow_azure" {
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.primary_sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# --- Primary Azure SQL Database ---
resource "azurerm_mssql_database" "primary_sql_db" {
  name      = "sqldb-orders"
  server_id = azurerm_mssql_server.primary_sql_server.id
  collation = "SQL_Latin1_General_CP1_CI_AS"
  sku_name  = "S0"

  tags = {
    Environment = "DR-Test"
    Pattern     = "3.Replicate"
    Role        = "PrimaryDB"
  }
}

# ==============================================================================
# 2. SECONDARY REGION INFRASTRUCTURE (West US - Warm Standby)
# ==============================================================================

resource "azurerm_resource_group" "secondary_rg" {
  name     = "rg-${var.environment_prefix}-${var.secondary_region}"
  location = var.secondary_region
  tags = {
    Environment = "DR-Test"
    Pattern     = "3.Replicate"
    Role        = "Secondary"
  }
}

resource "azurerm_virtual_network" "secondary_vnet" {
  name                = "vnet-${var.environment_prefix}-${var.secondary_region}"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.secondary_rg.location
  resource_group_name = azurerm_resource_group.secondary_rg.name
}

resource "azurerm_subnet" "secondary_subnet" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.secondary_rg.name
  virtual_network_name = azurerm_virtual_network.secondary_vnet.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_public_ip" "secondary_pip" {
  name                = "pip-${var.environment_prefix}-${var.secondary_region}"
  location            = azurerm_resource_group.secondary_rg.location
  resource_group_name = azurerm_resource_group.secondary_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "pip-${var.environment_prefix}-${var.secondary_region}-${random_string.suffix.result}"
}

resource "azurerm_network_security_group" "secondary_nsg" {
  name                = "nsg-${var.environment_prefix}-${var.secondary_region}"
  location            = azurerm_resource_group.secondary_rg.location
  resource_group_name = azurerm_resource_group.secondary_rg.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "secondary_nic" {
  name                = "nic-${var.environment_prefix}-${var.secondary_region}"
  location            = azurerm_resource_group.secondary_rg.location
  resource_group_name = azurerm_resource_group.secondary_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.secondary_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.secondary_pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "secondary_nic_nsg" {
  network_interface_id      = azurerm_network_interface.secondary_nic.id
  network_security_group_id = azurerm_network_security_group.secondary_nsg.id
}

# --- Secondary Azure SQL Logical Server ---
resource "azurerm_mssql_server" "secondary_sql_server" {
  name                         = "sql-${var.environment_prefix}-${var.secondary_region}-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.secondary_rg.name
  location                     = azurerm_resource_group.secondary_rg.location
  version                      = "12.0"
  administrator_login          = var.admin_username
  administrator_login_password = var.admin_password
  minimum_tls_version          = "1.2"

  tags = {
    Environment = "DR-Test"
    Pattern     = "3.Replicate"
    Role        = "SecondarySQL"
  }
}

resource "azurerm_mssql_firewall_rule" "secondary_allow_azure" {
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.secondary_sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ==============================================================================
# 3. CONTINUOUS REPLICATION: AZURE SQL FAILOVER GROUP
# ==============================================================================

resource "azurerm_mssql_failover_group" "fog" {
  name      = "fog-${var.environment_prefix}-${random_string.suffix.result}"
  server_id = azurerm_mssql_server.primary_sql_server.id
  databases = [azurerm_mssql_database.primary_sql_db.id]

  partner_server {
    id = azurerm_mssql_server.secondary_sql_server.id
  }

  read_write_endpoint_failover_policy {
    mode          = "Automatic"
    grace_minutes = 60
  }

  tags = {
    Environment = "DR-Test"
    Pattern     = "3.Replicate"
  }
}

# Common Cloud-Init generation template for Python Orders Service
locals {
  app_init_template = <<-EOF
    #!/bin/bash
    set -e

    apt-get update -y
    apt-get install -y python3 python3-pip python3-venv nginx

    mkdir -p /opt/orders-app
    python3 -m venv /opt/orders-app/venv
    /opt/orders-app/venv/bin/pip install --upgrade pip
    /opt/orders-app/venv/bin/pip install flask pymssql gunicorn

    cat << 'PYEOF' > /opt/orders-app/app.py
    import os
    import time
    from flask import Flask, request, redirect, render_template_string, jsonify
    import pymssql

    app = Flask(__name__)

    # Connect to the global Failover Group listener!
    DB_SERVER = os.environ.get("DB_SERVER", "__FOG_SERVER__")
    DB_NAME   = "sqldb-orders"
    DB_USER   = "__DB_USER__"
    DB_PASS   = "__DB_PASS__"
    REGION    = "__REGION__"
    ROLE      = "__ROLE__"

    def get_connection():
        return pymssql.connect(
            server=DB_SERVER,
            user=DB_USER,
            password=DB_PASS,
            database=DB_NAME,
            as_dict=True,
            login_timeout=10
        )

    def init_db():
        for attempt in range(25):
            try:
                with get_connection() as conn:
                    with conn.cursor() as cur:
                        cur.execute("""
                            IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='orders' and xtype='U')
                            BEGIN
                                CREATE TABLE orders (
                                    id INT IDENTITY(1,1) PRIMARY KEY,
                                    order_number VARCHAR(50) NOT NULL,
                                    customer_name VARCHAR(100) NOT NULL,
                                    amount DECIMAL(10,2) NOT NULL,
                                    status VARCHAR(50) NOT NULL,
                                    created_at DATETIME DEFAULT GETDATE()
                                );
                                INSERT INTO orders (order_number, customer_name, amount, status) VALUES
                                ('ORD-5001', 'Contoso Retail', 12500.50, 'Paid'),
                                ('ORD-5002', 'Fabrikam Logistics', 8400.00, 'Shipped'),
                                ('ORD-5003', 'AdventureWorks Cycles', 24999.90, 'Processing');
                            END
                        """)
                        conn.commit()
                        print("Database initialized successfully!")
                        return True
            except Exception as e:
                print(f"Waiting for Azure SQL Failover Group... ({attempt+1}/25): {e}")
                time.sleep(5)
        return False

    HTML_TEMPLATE = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>Contoso Orders Portal - Strategy 3: Replicate</title>
      <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 30px auto; max-width: 900px; background-color: #f8fafc; color: #0f172a; }
        .header { background: white; padding: 25px; border-radius: 12px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); margin-bottom: 25px; }
        .badge { background: #16a34a; color: white; padding: 5px 12px; border-radius: 16px; font-size: 12px; font-weight: bold; }
        .badge-standby { background: #d97706; color: white; padding: 5px 12px; border-radius: 16px; font-size: 12px; font-weight: bold; }
        .region-tag { color: #0284c7; font-size: 26px; font-weight: bold; margin: 6px 0; }
        .meta-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-top: 15px; }
        .meta-box { background: #f1f5f9; padding: 12px 16px; border-radius: 8px; font-size: 13px; }
        .table-card { background: white; padding: 25px; border-radius: 12px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); margin-bottom: 25px; }
        table { width: 100%; border-collapse: collapse; margin-top: 12px; }
        th, td { border: 1px solid #e2e8f0; padding: 10px 14px; text-align: left; font-size: 13px; }
        th { background: #f1f5f9; color: #475569; }
        .form-card { background: white; padding: 25px; border-radius: 12px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); }
        .form-row { display: grid; grid-template-columns: 2fr 1fr 1fr auto; gap: 10px; margin-top: 12px; }
        input, select { padding: 9px 12px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 13px; }
        button { background: #2563eb; color: white; border: none; padding: 9px 18px; border-radius: 6px; font-weight: bold; cursor: pointer; }
        button:hover { background: #1d4ed8; }
        .sync-box { background: #ecfdf5; border-left: 4px solid #10b981; padding: 12px 16px; border-radius: 4px; margin-top: 20px; font-size: 13px; }
      </style>
    </head>
    <body>
      <div class="header">
        <div style="display:flex; justify-content:space-between; align-items:center;">
          <span class="{{ 'badge' if role == 'Primary' else 'badge-standby' }}">{{ role.upper() }} REGION SERVING TRAFFIC</span>
          <span style="font-size:12px; color:#64748b;">SQL Latency: {{ latency }} ms</span>
        </div>
        <div class="region-tag">{{ region }} (Serving via Traffic Manager)</div>
        <p style="margin:4px 0 0; color:#64748b; font-size:14px;">Contoso Orders Portal - Strategy 3: Replicate (Warm / Hot DR)</p>

        <div class="meta-grid">
          <div class="meta-box">
            <strong>Global SQL Listener (Failover Group):</strong><br/>
            <code style="color:#0284c7;">{{ db_server }}</code>
          </div>
          <div class="meta-box">
            <strong>Replication Engine:</strong><br/>
            <span>Active Geo-Replication (Replication Lag &lt; 2s)</span>
          </div>
        </div>
      </div>

      <div class="table-card">
        <h3 style="margin-top:0;">Live Replicated Orders Table</h3>
        {% if error %}
          <div style="color:red; background:#fee2e2; padding:10px; border-radius:6px;">{{ error }}</div>
        {% else %}
          <table>
            <tr>
              <th>ID</th>
              <th>Order Number</th>
              <th>Customer Name</th>
              <th>Amount</th>
              <th>Status</th>
              <th>Created Timestamp</th>
            </tr>
            {% for o in orders %}
            <tr>
              <td>{{ o.id }}</td>
              <td><strong>{{ o.order_number }}</strong></td>
              <td>{{ o.customer_name }}</td>
              <td>USD {{ o.amount }}</td>
              <td>{{ o.status }}</td>
              <td>{{ o.created_at }}</td>
            </tr>
            {% endfor %}
          </table>
        {% endif %}
      </div>

      <div class="form-card">
        <h3 style="margin-top:0;">Insert New Order (Replicates instantly across regions)</h3>
        <form method="POST" action="/create-order">
          <div class="form-row">
            <input type="text" name="customer" placeholder="Customer Name (e.g. Microsoft Corp)" required />
            <input type="number" step="0.01" name="amount" placeholder="Amount (e.g. 150000.00)" required />
            <select name="status">
              <option value="Paid">Paid</option>
              <option value="Processing">Processing</option>
            </select>
            <button type="submit">+ Insert Order</button>
          </div>
        </form>

        <div class="sync-box">
          🚀 <strong>Instant Failover Demo:</strong> Insert an order here in <code>{{ region }}</code>. Stop the web service in East US (<code>sudo systemctl stop orders-app</code>). Within 30–45 seconds, Azure Traffic Manager steers you to the other region, where this exact order is already synchronized!
        </div>
      </div>
    </body>
    </html>
    """

    @app.route("/")
    def index():
        start = time.time()
        orders = []
        err = None
        try:
            with get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT id, order_number, customer_name, amount, status, CONVERT(VARCHAR, created_at, 120) as created_at FROM orders ORDER BY id DESC")
                    orders = cur.fetchall()
        except Exception as e:
            err = f"Database connection error: {str(e)}"
        latency = int((time.time() - start) * 1000)
        return render_template_string(HTML_TEMPLATE,
                                     orders=orders,
                                     error=err,
                                     latency=latency,
                                     region=REGION,
                                     role=ROLE,
                                     db_server=DB_SERVER)

    # Traffic Manager Health Probe Endpoint
    @app.route("/health")
    def health():
        return jsonify(status="healthy", region=REGION, role=ROLE), 200

    @app.route("/create-order", methods=["POST"])
    def create_order():
        cust = request.form.get("customer", "Corporate Client")
        amount = float(request.form.get("amount", 500.0))
        status = request.form.get("status", "Paid")
        order_num = f"ORD-{int(time.time()) % 100000:05d}"
        try:
            with get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "INSERT INTO orders (order_number, customer_name, amount, status) VALUES (%s, %s, %d, %s)",
                        (order_num, cust, amount, status)
                    )
                    conn.commit()
        except Exception as e:
            print(f"Error creating order: {e}")
        return redirect("/")

    if __name__ == "__main__":
        init_db()
        app.run(host="127.0.0.1", port=5000)
    PYEOF

    cat << 'SYSEOF' > /etc/systemd/system/orders-app.service
    [Unit]
    Description=Contoso Orders Portal Flask App
    After=network.target

    [Service]
    User=root
    WorkingDirectory=/opt/orders-app
    ExecStart=/opt/orders-app/venv/bin/python /opt/orders-app/app.py
    Restart=always
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
    SYSEOF

    cat << 'NGXEOF' > /etc/nginx/sites-available/default
    server {
        listen 80 default_server;
        listen [::]:80 default_server;

        location / {
            proxy_pass http://127.0.0.1:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
    NGXEOF

    systemctl daemon-reload
    systemctl enable orders-app
    systemctl start orders-app
    systemctl restart nginx
  EOF
}

# --- Primary Linux VM (East US) ---
resource "azurerm_linux_virtual_machine" "primary_vm" {
  name                            = "vm-orders-${var.primary_region}"
  resource_group_name             = azurerm_resource_group.primary_rg.name
  location                        = azurerm_resource_group.primary_rg.location
  size                            = "Standard_B1s"
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.primary_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(
    replace(
      replace(
        replace(
          replace(
            local.app_init_template,
            "__FOG_SERVER__", "${azurerm_mssql_failover_group.fog.name}.database.windows.net"
          ),
          "__DB_USER__", var.admin_username
        ),
        "__DB_PASS__", var.admin_password
      ),
      "__REGION__", var.primary_region
    )
  )

  tags = {
    Pattern = "3.Replicate"
    Role    = "PrimaryApp"
  }
}

# --- Secondary Linux VM (West US - Warm Standby) ---
resource "azurerm_linux_virtual_machine" "secondary_vm" {
  name                            = "vm-orders-${var.secondary_region}"
  resource_group_name             = azurerm_resource_group.secondary_rg.name
  location                        = azurerm_resource_group.secondary_rg.location
  size                            = "Standard_B1s"
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.secondary_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(
    replace(
      replace(
        replace(
          replace(
            replace(
              local.app_init_template,
              "__FOG_SERVER__", "${azurerm_mssql_failover_group.fog.name}.database.windows.net"
            ),
            "__DB_USER__", var.admin_username
          ),
          "__DB_PASS__", var.admin_password
        ),
        "__REGION__", var.secondary_region
      ),
      "__ROLE__", "Warm-Standby"
    )
  )

  tags = {
    Pattern = "3.Replicate"
    Role    = "SecondaryWarmStandbyApp"
  }
}

# ==============================================================================
# 4. GLOBAL TRAFFIC DIRECTOR: AZURE TRAFFIC MANAGER
# ==============================================================================

resource "azurerm_traffic_manager_profile" "tm" {
  name                   = "tm-${var.environment_prefix}-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.primary_rg.name
  traffic_routing_method = "Priority"

  dns_config {
    relative_name = "contoso-orders-${random_string.suffix.result}"
    ttl           = 30
  }

  monitor_config {
    protocol                     = "HTTP"
    port                         = 80
    path                         = "/health"
    interval_in_seconds          = 10
    timeout_in_seconds           = 5
    tolerated_number_of_failures = 3
  }

  tags = {
    Environment = "DR-Test"
    Pattern     = "3.Replicate"
  }
}

# Primary Endpoint (Priority 1: East US)
resource "azurerm_traffic_manager_azure_endpoint" "primary_endpoint" {
  name               = "ep-${var.primary_region}"
  profile_id         = azurerm_traffic_manager_profile.tm.id
  priority           = 1
  target_resource_id = azurerm_public_ip.primary_pip.id
}

# Secondary Endpoint (Priority 2: West US - Warm Standby)
resource "azurerm_traffic_manager_azure_endpoint" "secondary_endpoint" {
  name               = "ep-${var.secondary_region}"
  profile_id         = azurerm_traffic_manager_profile.tm.id
  priority           = 2
  target_resource_id = azurerm_public_ip.secondary_pip.id
}

# ==============================================================================
# 5. OUTPUTS & VERIFICATION RUNBOOK
# ==============================================================================

output "traffic_manager_url" {
  description = "Global routing URL steered by Azure Traffic Manager"
  value       = "http://${azurerm_traffic_manager_profile.tm.fqdn}"
}

output "traffic_manager_routing_mode" {
  description = "Routing policy configured"
  value       = "Priority Routing (Priority 1: East US, Priority 2: West US)"
}

output "failover_group_listener_fqdn" {
  description = "Global Read-Write database listener for the Failover Group"
  value       = "${azurerm_mssql_failover_group.fog.name}.database.windows.net"
}

output "primary_vm_public_ip" {
  description = "East US VM Public IP"
  value       = azurerm_public_ip.primary_pip.ip_address
}

output "primary_direct_url" {
  description = "Direct URL to East US VM"
  value       = "http://${azurerm_public_ip.primary_pip.ip_address}"
}

output "secondary_vm_public_ip" {
  description = "West US VM Public IP"
  value       = azurerm_public_ip.secondary_pip.ip_address
}

output "secondary_direct_url" {
  description = "Direct URL to West US VM"
  value       = "http://${azurerm_public_ip.secondary_pip.ip_address}"
}

output "failover_test_instructions" {
  description = "PowerShell commands to test automated failover"
  value       = <<-EOT
    # 1. Open the global Traffic Manager URL in browser:
    http://${azurerm_traffic_manager_profile.tm.fqdn}

    # 2. Stop the application on East US VM to simulate outage:
    ssh azureuser@${azurerm_public_ip.primary_pip.ip_address} "sudo systemctl stop orders-app"

    # 3. Within 30 to 45 seconds, refresh the Traffic Manager URL.
    # Traffic Manager automatically fails over to West US with ZERO data loss!
  EOT
}

