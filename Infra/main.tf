terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "prefix" {
  type        = string
  default     = "new"
  description = "description"
}


data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}Azure-Functions"
  location = "East US"
}

resource "azurerm_application_insights" "ai" {
  name                = "${var.prefix}appinsightsai"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
}


resource "azurerm_storage_account" "source_storage" {
  name                     = "${var.prefix}srcblobstrgacc"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_account" "dest_storage" {
  name                     = "${var.prefix}destblobaccount"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

# Create source blob storage container
resource "azurerm_storage_container" "source_container" {
  depends_on = [azurerm_storage_account.source_storage]

  name                  = "demo-data"
  container_access_type = "private"
  storage_account_name  = azurerm_storage_account.source_storage.name
}

# Create destination blob storage container
resource "azurerm_storage_container" "dest_container" {
  depends_on = [azurerm_storage_account.dest_storage]
  
  name                  = "demo-data"
  container_access_type = "private"
  storage_account_name  = azurerm_storage_account.dest_storage.name
}

resource "azurerm_service_plan" "app_service_plan" {
  name                = "${var.prefix}appserviceplan"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  os_type             = "Linux"
  sku_name            = "Y1"
}

# data "archive_file" "file_function_app" {
#   type        = "zip"
#   source_dir  = "../TriggerTask"
#   output_path = "TriggerTask.zip"
# }

resource "azurerm_linux_function_app" "function_app" {
  depends_on = [azurerm_service_plan.app_service_plan]

  name                       = "${var.prefix}-func-main"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.source_storage.name
  storage_account_access_key = azurerm_storage_account.source_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.app_service_plan.id
  # zip_deploy_file = data.archive_file.file_function_app.output_path

   site_config {
    application_stack {
      python_version = "3.10"
    }  
  }
  app_settings = {
    "AzureWebJobsStorage" = azurerm_storage_account.source_storage.primary_connection_string,
    "blobstorageaccountsource_STORAGE" = azurerm_storage_account.source_storage.primary_connection_string,
    "blobstorageaccountdestination_STORAGE" = azurerm_storage_account.dest_storage.primary_connection_string,
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.ai.instrumentation_key,
    "SCM_DO_BUILD_DURING_DEPLOYMENT"=true,
    "WEBSITE_RUN_FROM_PACKAGE" = 1
  }
}