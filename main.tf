# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.75.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "StorageRGMariaabr"
    storage_account_name = "taskboardstoragemariaabr"
    container_name       = "taskboardcontainermariaabr"
    key                  = "terraform.tfstate"
  }
}


provider "azurerm" {
  skip_provider_registration = true
  features {}
}

# Generate a random integer to create a globally uniquie name
resource "random_integer" "ri" {
  min = 10000
  max = 99999
}

# Create the resource group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

# Create the Linux App Service Plan
resource "azurerm_service_plan" "asp" {
  name                = var.app_service_plan_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "F1"
}

resource "azurerm_mssql_server" "mssql_server" {
  name                         = var.sql_server_name
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password
}

#	Create a database resource in Azure with name, server ID, collation, license type, SKU name and zone redundancy arguments
resource "azurerm_mssql_database" "mssql_database" {
  name           = var.sql_database_name
  server_id      = azurerm_mssql_server.mssql_server.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  sku_name       = "S0"
  zone_redundant = false
}

# Create a firewall rule for the Azure server, which has a name and server ID and sets "0.0.0.0" as start and end IP addresses (this means that it allows other Azure resources to access the server)
resource "azurerm_mssql_firewall_rule" "mssql_fw_rule" {
  name             = var.firewall_rule_name
  server_id        = azurerm_mssql_server.mssql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}


# Create the web app, pass in rge App Service Plan ID
resource "azurerm_linux_web_app" "app" {
  name                = var.app_service_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_service_plan.asp.location
  service_plan_id     = azurerm_service_plan.asp.id

  site_config {
    application_stack {
      dotnet_version = "6.0"
    }
    always_on = false
  }
  connection_string {
    name  = "Default Connection"
    type  = "SQLAzure"
    value = "Data Source=tcp:${azurerm_mssql_server.mssql_server.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.mssql_database.name};User ID=${azurerm_mssql_server.mssql_server.administrator_login};Password=${azurerm_mssql_server.mssql_server.administrator_login_password};Trusted_Connection=False; MultipleActiveResultSets=True;"
  }
}

# Deploy code from a public GitHub repo
resource "azurerm_app_service_source_control" "assc" {
  app_id                 = azurerm_linux_web_app.app.id
  repo_url               = var.repo_URL
  branch                 = "main"
  use_manual_integration = true
}
