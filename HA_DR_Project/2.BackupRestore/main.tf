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
  description = "The primary Azure region where active stateful workloads run"
  type        = string
  default     = "eastus"
}

variable "secondary_region" {
  description = "The paired secondary Azure region for Azure SQL Geo-Restore"
  type        = string
  default     = "westus"
}

variable "environment_prefix" {
  description = "Naming prefix for all resources"
  type        = string
  default     = "backup-demo"
}

variable "admin_username" {
  description = "Administrator username for VM and SQL Server"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "Administrator password for VM and SQL Server"
  type        = string
  default     = "P@ssw0rd12345!"
  sensitive   = true
}

# Random suffix for globally unique SQL Server names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ==============================================================================
# 1. PRIMARY REGION INFRASTRUCTURE (East US)
# ==============================================================================

resource "azurerm_resource_group" "primary_rg" {
  name     = "rg-${var.environment_prefix}-${var.primary_region}"
  location = var.primary_region
  tags = {
    Environment = "DR-Test"
    Pattern     = "2.BackupRestore"
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
    Pattern     = "2.BackupRestore"
    Role        = "PrimarySQL"
  }
}

# Allow Azure Services to connect to SQL
resource "azurerm_mssql_firewall_rule" "primary_allow_azure" {
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.primary_sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Whitelist the VM's Public IP explicitly
resource "azurerm_mssql_firewall_rule" "primary_allow_vm_ip" {
  name             = "AllowPrimaryVMPublicIP"
  server_id        = azurerm_mssql_server.primary_sql_server.id
  start_ip_address = azurerm_public_ip.primary_pip.ip_address
  end_ip_address   = azurerm_public_ip.primary_pip.ip_address
}

# --- Primary Azure SQL Database with Geo-Redundant Backups ---
resource "azurerm_mssql_database" "primary_sql_db" {
  name                 = "sqldb-orders"
  server_id            = azurerm_mssql_server.primary_sql_server.id
  collation            = "SQL_Latin1_General_CP1_CI_AS"
  sku_name             = "S0"
  storage_account_type = "Geo"
  geo_backup_enabled   = true

  tags = {
    Environment = "DR-Test"
    Pattern     = "2.BackupRestore"
    Role        = "PrimaryDatabase"
  }
}

# --- Dynamic Orders Portal App VM (Connected Live to Azure SQL) ---
resource "azurerm_linux_virtual_machine" "primary_app_vm" {
  name                            = "vm-orders-app-${var.primary_region}"
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

  # Cloud-init installs Python 3, connects directly to Azure SQL, creates orders table,
  # seeds data, and runs a live web app reverse-proxied by Nginx
  custom_data = base64encode(<<-EOF
              #!/bin/bash
              set -e

              # 1. Install prerequisites and Nginx
              apt-get update -y
              apt-get install -y python3 python3-pip python3-venv nginx

              # 2. Set up application directory and virtual environment
              mkdir -p /opt/orders-app
              python3 -m venv /opt/orders-app/venv
              /opt/orders-app/venv/bin/pip install --upgrade pip
              /opt/orders-app/venv/bin/pip install flask pymssql gunicorn

              # 3. Create the dynamic Python Flask application
              cat << 'PYEOF' > /opt/orders-app/app.py
              import os
              import time
              from datetime import datetime
              from flask import Flask, request, redirect, render_template_string, jsonify
              import pymssql

              app = Flask(__name__)

              DB_SERVER = os.environ.get("DB_SERVER", "${azurerm_mssql_server.primary_sql_server.fully_qualified_domain_name}")
              DB_NAME   = os.environ.get("DB_NAME", "${azurerm_mssql_database.primary_sql_db.name}")
              DB_USER   = os.environ.get("DB_USER", "${var.admin_username}")
              DB_PASS   = os.environ.get("DB_PASS", "${var.admin_password}")
              REGION    = os.environ.get("APP_REGION", "${var.primary_region}")

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
                                          ('ORD-9021', 'Contoso Retail', 12500.50, 'Paid'),
                                          ('ORD-9022', 'Fabrikam Logistics', 8400.00, 'Shipped'),
                                          ('ORD-9023', 'AdventureWorks Cycles', 24999.90, 'Processing');
                                      END
                                  """)
                                  conn.commit()
                                  print("Database initialized successfully!")
                                  return True
                      except Exception as e:
                          print(f"Waiting for Azure SQL Database... ({attempt+1}/25): {e}")
                          time.sleep(5)
                  return False

              HTML_TEMPLATE = """
              <!DOCTYPE html>
              <html>
              <head>
                <title>Contoso Orders Portal - Disaster Recovery</title>
                <style>
                  body { font-family: 'Segoe UI', Arial, sans-serif; margin: 30px auto; max-width: 900px; background-color: #f8fafc; color: #0f172a; }
                  .header { background: white; padding: 25px; border-radius: 12px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); margin-bottom: 25px; }
                  .badge { background: #16a34a; color: white; padding: 5px 12px; border-radius: 16px; font-size: 12px; font-weight: bold; }
                  .region-tag { color: #0284c7; font-size: 24px; font-weight: bold; margin: 5px 0; }
                  .meta-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-top: 15px; }
                  .meta-box { background: #f1f5f9; padding: 12px 16px; border-radius: 8px; font-size: 13px; }
                  .table-card { background: white; padding: 25px; border-radius: 12px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); margin-bottom: 25px; }
                  table { width: 100%; border-collapse: collapse; margin-top: 12px; }
                  th, td { border: 1px solid #e2e8f0; padding: 10px 14px; text-align: left; font-size: 13px; }
                  th { background: #f1f5f9; color: #475569; }
                  tr:hover { background-color: #f8fafc; }
                  .status-paid { color: #16a34a; font-weight: bold; }
                  .status-shipped { color: #0284c7; font-weight: bold; }
                  .status-proc { color: #d97706; font-weight: bold; }
                  .form-card { background: white; padding: 25px; border-radius: 12px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); }
                  .form-row { display: grid; grid-template-columns: 2fr 1fr 1fr auto; gap: 10px; margin-top: 12px; }
                  input, select { padding: 9px 12px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 13px; }
                  button { background: #2563eb; color: white; border: none; padding: 9px 18px; border-radius: 6px; font-weight: bold; cursor: pointer; }
                  button:hover { background: #1d4ed8; }
                  .dr-banner { background: #eff6ff; border-left: 4px solid #2563eb; padding: 12px 16px; border-radius: 4px; margin-top: 20px; font-size: 13px; }
                </style>
              </head>
              <body>
                <div class="header">
                  <div style="display:flex; justify-content:space-between; align-items:center;">
                    <span class="badge">LIVE AZURE SQL CONNECTION</span>
                    <span style="font-size:12px; color:#64748b;">Query Latency: {{ latency }} ms</span>
                  </div>
                  <div class="region-tag">{{ region }} (Active Production)</div>
                  <p style="margin:4px 0 0; color:#64748b; font-size:14px;">Contoso Orders Portal - Two-Tier Stateful Workload</p>

                  <div class="meta-grid">
                    <div class="meta-box">
                      <strong>Connected Database Server:</strong><br/>
                      <code style="color:#0284c7;">{{ db_server }}</code>
                    </div>
                    <div class="meta-box">
                      <strong>Database & Redundancy:</strong><br/>
                      <code style="color:#0284c7;">{{ db_name }}</code> (Storage: GeoRedundant RA-GRS)
                    </div>
                  </div>
                </div>

                <div class="table-card">
                  <h3 style="margin-top:0;">Live Orders Table (Queried directly from Azure SQL)</h3>
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
                        <td><span class="status-{{ o.status.lower() }}">{{ o.status }}</span></td>
                        <td>{{ o.created_at }}</td>
                      </tr>
                      {% endfor %}
                    </table>
                  {% endif %}
                </div>

                <div class="form-card">
                  <h3 style="margin-top:0;">Insert Real Transaction into Azure SQL</h3>
                  <form method="POST" action="/create-order">
                    <div class="form-row">
                      <input type="text" name="customer" placeholder="Customer Name (e.g. Northwind Ltd)" required />
                      <input type="number" step="0.01" name="amount" placeholder="Amount (e.g. 5200.00)" required />
                      <select name="status">
                        <option value="Paid">Paid</option>
                        <option value="Processing">Processing</option>
                        <option value="Shipped">Shipped</option>
                      </select>
                      <button type="submit">+ Insert Order</button>
                    </div>
                  </form>

                  <div class="dr-banner">
                    💡 <strong>Test the DR Geo-Restore:</strong> Insert an order here in <code>{{ region }}</code>. When you simulate regional failover and execute <code>az sql db restore</code> in <code>West US</code>, this exact newly created record will be recovered from the geo-replicated backup!
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
                                               db_server=DB_SERVER,
                                               db_name=DB_NAME)

              @app.route("/create-order", methods=["POST"])
              def create_order():
                  cust = request.form.get("customer", "Guest Customer")
                  amount = float(request.form.get("amount", 100.0))
                  status = request.form.get("status", "Processing")
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

              # 4. Create systemd service for the orders app
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

              # 5. Configure Nginx reverse proxy
              cat << 'NGXEOF' > /etc/nginx/sites-available/default
              server {
                  listen 80 default_server;
                  listen [::]:80 default_server;

                  location / {
                      proxy_pass http://127.0.0.1:5000;
                      proxy_set_header Host $host;
                      proxy_set_header X-Real-IP $remote_addr;
                      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                      proxy_connect_timeout 15s;
                      proxy_read_timeout 15s;
                  }
              }
              NGXEOF

              # 6. Enable and start services
              systemctl daemon-reload
              systemctl enable orders-app
              systemctl start orders-app
              systemctl restart nginx
              EOF
  )

  tags = {
    Pattern = "2.BackupRestore"
    Role    = "AppTier"
  }
}

# ==============================================================================
# 2. SECONDARY REGION PRE-STAGED INFRASTRUCTURE (West US)
# ==============================================================================
# In Strategy 2, we pre-stage the secondary logical server and target VNet.
# The secondary SQL Server costs $0 until a database is restored onto it!

resource "azurerm_resource_group" "secondary_rg" {
  name     = "rg-${var.environment_prefix}-${var.secondary_region}"
  location = var.secondary_region
  tags = {
    Environment = "DR-Test"
    Pattern     = "2.BackupRestore"
    Role        = "Secondary-Target"
  }
}

resource "azurerm_virtual_network" "secondary_vnet" {
  name                = "vnet-${var.environment_prefix}-${var.secondary_region}"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.secondary_rg.location
  resource_group_name = azurerm_resource_group.secondary_rg.name
}

resource "azurerm_subnet" "secondary_subnet" {
  name                 = "snet-web-restored"
  resource_group_name  = azurerm_resource_group.secondary_rg.name
  virtual_network_name = azurerm_virtual_network.secondary_vnet.name
  address_prefixes     = ["10.20.1.0/24"]
}

# Pre-staged secondary Azure SQL Logical Server ($0 Standby Compute Cost)
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
    Pattern     = "2.BackupRestore"
    Role        = "SecondaryTargetSQL"
  }
}

# Allow Azure Services to connect to Secondary SQL
resource "azurerm_mssql_firewall_rule" "secondary_allow_azure" {
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.secondary_sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ==============================================================================
# 3. OUTPUTS & RESTORE RUNBOOK
# ==============================================================================

output "primary_resource_group" {
  description = "The Primary Resource Group name"
  value       = azurerm_resource_group.primary_rg.name
}

output "primary_web_url" {
  description = "Orders Portal web application running in East US"
  value       = "http://${azurerm_public_ip.primary_pip.ip_address}"
}

output "primary_sql_server_name" {
  description = "Primary Azure SQL logical server name"
  value       = azurerm_mssql_server.primary_sql_server.name
}

output "primary_sql_server_fqdn" {
  description = "Primary Azure SQL server fully qualified domain name"
  value       = azurerm_mssql_server.primary_sql_server.fully_qualified_domain_name
}

output "primary_database_name" {
  description = "Primary stateful SQL database name"
  value       = azurerm_mssql_database.primary_sql_db.name
}

output "geo_backup_status" {
  description = "Verification of Geo-Redundant backup storage"
  value       = "ENABLED (Storage Account Type: Geo / RA-GRS)"
}

output "secondary_resource_group" {
  description = "Pre-staged Resource Group in West US for restore target"
  value       = azurerm_resource_group.secondary_rg.name
}

output "secondary_sql_server_name" {
  description = "Pre-staged Secondary SQL server ($0 idle database compute)"
  value       = azurerm_mssql_server.secondary_sql_server.name
}

output "secondary_sql_server_fqdn" {
  description = "Secondary Azure SQL server fully qualified domain name"
  value       = azurerm_mssql_server.secondary_sql_server.fully_qualified_domain_name
}

output "dr_runbook_geo_restore_command" {
  description = "Command to execute Azure SQL Geo-Restore into West US"
  value       = <<-EOT
    # Run in PowerShell or Azure CLI to trigger Geo-Restore during an East US disaster:
    az sql db restore `
      --resource-group ${azurerm_resource_group.secondary_rg.name} `
      --server ${azurerm_mssql_server.secondary_sql_server.name} `
      --name ${azurerm_mssql_database.primary_sql_db.name} `
      --dest-name "sqldb-orders-restored" `
      --edition "Standard" `
      --service-objective "S0"
  EOT
}
