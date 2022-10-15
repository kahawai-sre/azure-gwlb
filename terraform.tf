
terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~>0.1"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.2.0"
    }
  }
}

