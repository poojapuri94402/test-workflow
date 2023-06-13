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
  default     = "task"
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

resource "azurerm_app_service_plan" "app_service_plan" {
  name                = "${var.prefix}appserviceplan"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  kind     = "FunctionApp"
  reserved = true

  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

data "archive_file" "file_function_app" {
  type        = "zip"
  source_dir  = "../TriggerTask"
  output_path = "TriggerTask.zip"
}

# Create source blob storage container for deployment
resource "azurerm_storage_container" "deployment_container" {
  depends_on = [azurerm_storage_account.source_storage]

  name                  = "deployment-release"
  container_access_type = "private"
  storage_account_name  = azurerm_storage_account.source_storage.name
}

resource "azurerm_storage_blob" "storage_blob" {
  name = "${filesha256(data.archive_file.file_function_app.output_path)}.zip"
  storage_account_name = azurerm_storage_account.source_storage.name
  storage_container_name = azurerm_storage_container.deployment_container.name
  type = "Block"
  source = data.archive_file.file_function_app.output_path
}

data "azurerm_storage_account_blob_container_sas" "storage_account_blob_container_sas" {
  connection_string = azurerm_storage_account.source_storage.primary_connection_string
  container_name    = azurerm_storage_container.deployment_container.name

  start = "2023-01-01T00:00:00Z"
  expiry = "2029-01-01T00:00:00Z"

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = false
  }
}

resource "azurerm_function_app" "function_app_main" {
  depends_on = [azurerm_app_service_plan.app_service_plan]

  name                       = "${var.prefix}-func-main"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  app_service_plan_id        = azurerm_app_service_plan.app_service_plan.id
  app_settings = {
    "WEBSITE_RUN_FROM_PACKAGE"    = "https://${azurerm_storage_account.source_storage.name}.blob.core.windows.net/${azurerm_storage_container.deployment_container.name}/${azurerm_storage_blob.storage_blob.name}${data.azurerm_storage_account_blob_container_sas.storage_account_blob_container_sas.sas}",
    "FUNCTIONS_WORKER_RUNTIME" = "python",
    "AzureWebJobsStorage" = azurerm_storage_account.source_storage.primary_connection_string,
    "blobstorageaccountsource_STORAGE" = azurerm_storage_account.source_storage.primary_connection_string,
    "blobstorageaccountdestination_STORAGE" = azurerm_storage_account.dest_storage.primary_connection_string,
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.ai.instrumentation_key
  }

  os_type = "linux"
  site_config {
    linux_fx_version ="Python|3.9"
    use_32_bit_worker_process = false
  }
  storage_account_name       = azurerm_storage_account.source_storage.name
  storage_account_access_key = azurerm_storage_account.source_storage.primary_access_key
  version                    = "~4"
}

resource "azurerm_function_app" "function_app" {
  depends_on = [azurerm_app_service_plan.app_service_plan]

  name                       = "${var.prefix}-func"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  app_service_plan_id        = azurerm_app_service_plan.app_service_plan.id
  app_settings = {
    "WEBSITE_RUN_FROM_PACKAGE"    = "1",
    "FUNCTIONS_WORKER_RUNTIME" = "python",
    "AzureWebJobsStorage" = azurerm_storage_account.source_storage.primary_connection_string,
    "blobstorageaccountsource_STORAGE" = azurerm_storage_account.source_storage.primary_connection_string,
    "blobstorageaccountdestination_STORAGE" = azurerm_storage_account.dest_storage.primary_connection_string,
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.ai.instrumentation_key
  }

  os_type = "linux"
  site_config {
    linux_fx_version ="Python|3.9"
    use_32_bit_worker_process = false
  }
  storage_account_name       = azurerm_storage_account.source_storage.name
  storage_account_access_key = azurerm_storage_account.source_storage.primary_access_key
  version                    = "~4"
}

locals {
    publish_code_command = "az functionapp deployment source config-zip -g ${azurerm_resource_group.rg.name} --n ${azurerm_function_app.function_app.name} --src ${data.archive_file.file_function_app.output_path}"
}

resource "null_resource" "code_deploy" {
  provisioner "local-exec" {
    command = local.publish_code_command
  }

  triggers = {
    input_json = filemd5(data.archive_file.file_function_app.output_path)
    publish_code_command = local.publish_code_command
  }

  depends_on = [azurerm_function_app.function_app, local.publish_code_command]
}