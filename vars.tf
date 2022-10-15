variable "mysourceip" {
    type = string
    #default = "125.xxx.xxx.xxx"
}

variable "deloymentname" {
    type = string
    description = "Unique suffix for deployed resources"
    default = "demo"
}

variable "connectivitySubscriptionId" {
  type    = string
  default = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}

variable "location" {
    type = string
    default = "australiaeast"
}

variable "vnet-gwlb-addressspace" {
    type = list
    default = ["10.200.0.0/16"]
}

variable "vnet-workload-addressspace" {
    type = list
    default = ["10.201.0.0/16"]
}

variable "subnet-gwlb-addressspace" {
    type = list
    default = ["10.200.0.0/24"]
}

variable "subnet-gwlb-azurebastion" {
    type = list
    default = ["10.200.1.0/24"]
}

variable "subnet-workload-addressspace" {
    type = list
    default = ["10.201.0.0/24"]
}

variable "subnet-workload-azurebastion" {
    type = list
    default = ["10.201.1.0/24"]
}



variable "vm_size" {
  type = string
  description = "Size (SKU) of the virtual machine to create"
  default = "Standard_B2s"
}

variable "admin_username" {
  description = "Username for Virtual Machine administrator account"
  type = string
  default = "adminlocal"
}

variable "admin_password" {
  description = "Password for Virtual Machine administrator account"
  type = string
  sensitive   = true
}

variable "ubuntu-publisher" {
  type        = string
  description = "Publisher ID for Ubuntu Linux" 
  default     = "Canonical" 
}

variable "ubuntu-offer" {
  type        = string
  description = "Offer ID for Ubuntu Linux" 
  default     = "UbuntuServer" 
}

variable "vxlan-vni-id-internal" {
  type        = string
  default     = "800" 
}

variable "vxlan-vtep-port-internal" {
  type        = string
  default     = "10800" 
}

variable "vxlan-vni-id-external" {
  type        = string
  default     = "801" 
}

variable "vxlan-vtep-port-external" {
  type        = string
  default     = "10801" 
}