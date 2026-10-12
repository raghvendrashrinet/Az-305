terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# --- Variables ---
variable "target_region" {
  description = "The target Azure region to deploy the stateless workload"
  type        = string
  default     = "eastus"
}

variable "environment_prefix" {
  description = "Prefix for all resources"
  type        = string
  default     = "recreate-demo"
}

# --- Resource Group ---
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.environment_prefix}-${var.target_region}"
  location = var.target_region
  tags = {
    Environment = "DR-Test"
    Pattern     = "1.Recreate"
  }
}

# --- Networking ---
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.environment_prefix}-${var.target_region}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                = "pip-${var.environment_prefix}-${var.target_region}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${var.environment_prefix}-${var.target_region}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

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
}

resource "azurerm_network_interface" "nic" {
  name                = "nic-${var.environment_prefix}-${var.target_region}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# --- Stateless Linux Web VM ---
resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "vm-${var.environment_prefix}-${var.target_region}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_B1s"
  admin_username                  = "azureuser"
  admin_password                  = "P@ssw0rd12345!"
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.nic.id]

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

  # Cloud-init installs nginx and creates a banner showing which region it is currently running in
  custom_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y nginx
              cat <<HTML > /var/www/html/index.html
              <!DOCTYPE html>
              <html>
              <head>
                <title>Disaster Recovery - Recreate Pattern</title>
                <style>
                  body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; background-color: #f4f6f8; }
                  .card { background: white; padding: 30px; border-radius: 12px; display: inline-block; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
                  .region { color: #0078D4; font-size: 28px; font-weight: bold; }
                  .badge { background: #28a745; color: white; padding: 6px 14px; border-radius: 20px; font-size: 14px; }
                </style>
              </head>
              <body>
                <div class="card">
                  <span class="badge">ACTIVE WORKLOAD</span>
                  <h1>Stateless Service Live</h1>
                  <p>Current Azure Region:</p>
                  <div class="region">${var.target_region}</div>
                  <p>Deployment Strategy: <strong>On-Demand Recreate via IaC</strong></p>
                </div>
              </body>
              </html>
              HTML
              systemctl enable nginx
              systemctl restart nginx
              EOF
  )
}

# --- Outputs ---
output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "region_deployed" {
  value = var.target_region
}

output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}

output "web_url" {
  value = "http://${azurerm_public_ip.pip.ip_address}"
}

