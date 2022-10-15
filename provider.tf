provider "azapi" {
    alias           = "connectivity-azapi"
    subscription_id = var.connectivitySubscriptionId
}

provider "azurerm" {
  alias           = "connectivity"
  subscription_id = var.connectivitySubscriptionId
  features {}
}