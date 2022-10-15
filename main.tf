#-  ================================================================================================
#-                             GWLB DEPLOYMENT REFERENCES:
#-  ================================================================================================
#-  azcli: https://medium.com/@OpenJNY/azure-gateway-load-balancer-with-linux-vm-as-nva-9568753e8b81
#-  bicep: https://github.com/dmauser/azure-gateway-lb/tree/main/bicep/modules/VM
#-  
#-  TRAFFIC FLOW SUMMARY:
#-  ================================================================================================
#-  External client => Public LB IP => GWLB internal VNI => NVA internal VTEP => <NVA packet processing> => NVA external VTEP => GWLB External VNI => Public LB => External client
#-
#-  NOTES:
#-  ================================================================================================
#-  !!! UPDATE vars.tf BEFORE CONTINUING !!!
#-  e.g.
#   variable "connectivitySubscriptionId" {
#     type    = string
#     default = "XXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXX"
#   }
#   variable "mysourceip" {
#     type = string
#     default = "125.xxx.xxx.xxx"
#   }

#// ------------- Base resources ------------

resource "azurerm_resource_group" "rg" {
    provider = azurerm.connectivity
    name      = "rg-${var.deloymentname}"
    location  = var.location
}

resource "azurerm_virtual_network" "vnet-gwlb" {
    provider = azurerm.connectivity
    name                = "vnet-gwlb-${var.deloymentname}"
    address_space       = var.vnet-gwlb-addressspace
    location            = var.location
    resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet-gwlb" {
    provider = azurerm.connectivity
    name = "subnet-gwlb-${var.deloymentname}"
    resource_group_name  = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet-gwlb.name
    address_prefixes     = var.subnet-gwlb-addressspace
}

resource "azurerm_subnet" "subnet-bastion-nva" {
    provider = azurerm.connectivity
    name = "AzureBastionSubnet"
    resource_group_name  = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet-gwlb.name
    address_prefixes     = var.subnet-gwlb-azurebastion
}

resource "azurerm_virtual_network" "vnet-workload" {
    provider            = azurerm.connectivity
    name                = "vnet-workload-${var.deloymentname}"
    address_space       = var.vnet-workload-addressspace
    location            = var.location
    resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet-workload" {
    provider = azurerm.connectivity
    name = "subnet-workload-${var.deloymentname}"
    resource_group_name  = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet-workload.name
    address_prefixes     = var.subnet-workload-addressspace
}

resource "azurerm_subnet" "subnet-bastion-workload" {
    provider = azurerm.connectivity
    name = "AzureBastionSubnet"
    resource_group_name  = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet-workload.name
    address_prefixes     = var.subnet-workload-azurebastion
}

resource "azurerm_network_security_group" "workload" {
  provider            = azurerm.connectivity
  name                = "nsg-workload"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "allowin" {
  provider            = azurerm.connectivity
  name                        = "allowin"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.mysourceip
  destination_address_prefix  = "*"
  resource_group_name  = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.workload.name
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  provider            = azurerm.connectivity
  subnet_id                 = azurerm_subnet.subnet-workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

#// ------------- Provider ------------------

#// 1. Create Gateway LB

resource "azurerm_lb" "gwlb-azure-ingress" {
    name                = "gwlb-azure-ingress"
    location            = var.location
    resource_group_name = azurerm_resource_group.rg.name
    provider = azurerm.connectivity
    sku = "Gateway"
    frontend_ip_configuration {
        name                            = "gwlb-fe-ip-config"
        subnet_id                       = azurerm_subnet.subnet-gwlb.id
        private_ip_address_allocation   = "Dynamic"
        private_ip_address_version      = "IPv4"
    }
}

resource "azurerm_lb_backend_address_pool" "gwlb-azure-ingress-backendaddresspool" {
    name                = "gwlb-azure-ingress-backendaddresspool"
    loadbalancer_id     = azurerm_lb.gwlb-azure-ingress.id
    provider = azurerm.connectivity
    tunnel_interface {
        type = "Internal"
        identifier = var.vxlan-vni-id-internal
        protocol = "VXLAN"
        port = var.vxlan-vtep-port-internal
    }
    tunnel_interface {
        type = "External"
        identifier = var.vxlan-vni-id-external
        protocol = "VXLAN"
        port = var.vxlan-vtep-port-external
    }
}

resource "azurerm_lb_probe" "gwlb-azure-ingress-nva-probe" {
    loadbalancer_id     = azurerm_lb.gwlb-azure-ingress.id
    name                = "gwlb-azure-ingress-nva-probe"
    provider = azurerm.connectivity
    protocol            = "Tcp"
    port                = 22
    interval_in_seconds = 5
    number_of_probes    = 2
}

resource "azurerm_lb_rule" "gwlb-azure-ingress-lb-all" {
    loadbalancer_id                 = azurerm_lb.gwlb-azure-ingress.id
    name                            = "gwlb-azure-ingress-lb-all"
    provider = azurerm.connectivity
    protocol                        = "All"
    frontend_port                   = 0
    backend_port                    = 0
    frontend_ip_configuration_name  = "gwlb-fe-ip-config"
    backend_address_pool_ids        = [azurerm_lb_backend_address_pool.gwlb-azure-ingress-backendaddresspool.id]
    disable_outbound_snat           = true
    probe_id                        = azurerm_lb_probe.gwlb-azure-ingress-nva-probe.id
}

#// 2. Create NVA VM NIC

resource "azurerm_network_interface" "gwlb-vm-nic" {
  name = "vm-nic"
  location = var.location
  resource_group_name = azurerm_resource_group.rg.name
  provider = azurerm.connectivity
  enable_ip_forwarding = true
  #enable_accelerated_networking = true - TODO: off for testing
  ip_configuration {
    name = "nva-nic-internal"
    subnet_id = azurerm_subnet.subnet-gwlb.id
    private_ip_address_allocation = "Dynamic"
    private_ip_address_version = "IPv4"
  }
}

#// 3. Associate NVA VM NIC with GWLB BackEnd Pool

resource "azurerm_network_interface_backend_address_pool_association" "gwlb-nva" {
  network_interface_id    = azurerm_network_interface.gwlb-vm-nic.id
  provider = azurerm.connectivity
  ip_configuration_name   = "nva-nic-internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.gwlb-azure-ingress-backendaddresspool.id
}

#// 4. Create NVA VM with VXLAN virtual interfaces and routing

resource "azurerm_linux_virtual_machine" "gwlb-nva" {
  depends_on=[azurerm_network_interface.gwlb-vm-nic]
  name = "gwlb-nva"
  location = var.location
  resource_group_name = azurerm_resource_group.rg.name
  provider = azurerm.connectivity
  network_interface_ids = [azurerm_network_interface.gwlb-vm-nic.id]
  size = var.vm_size
  source_image_reference {
    publisher = var.ubuntu-publisher
    offer = var.ubuntu-offer
    sku = "18.04-LTS"
    version = "latest"
  }
  os_disk {
    name = "gwlb-osdisk"
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  computer_name = "gwlb-vm"
  admin_username = var.admin_username
  admin_password = var.admin_password
  disable_password_authentication = false
}

#// 5. Create Public Load Balancer Public IP for consumer side LB
#//    (need the IP to configure the route on NVA - refer gwlb.sh)

resource "azurerm_public_ip" "pip-lb-ingress" {
  name                = "pip-lb-ingress"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  provider = azurerm.connectivity
  sku = "Standard"
  allocation_method   = "Static"
}

#// 6. Configure NVA (gwlb.sh)

data "template_file" "settings" {
  depends_on = [azurerm_public_ip.pip-lb-ingress, azurerm_lb.gwlb-azure-ingress]
  template = file("gwlb.sh")
  vars = {
    tunnel_internal_vni   = var.vxlan-vni-id-internal
    tunnel_internal_port  = var.vxlan-vtep-port-internal
    tunnel_external_vni   = var.vxlan-vni-id-external
    tunnel_external_port  = var.vxlan-vtep-port-external
    gwlb_lb_ip            = azurerm_lb.gwlb-azure-ingress.private_ip_address
    public_lb_ip          = azurerm_public_ip.pip-lb-ingress.ip_address
  }
}

resource "azurerm_virtual_machine_extension" "nva" {
    depends_on = [azurerm_public_ip.pip-lb-ingress]
    name                  = "nva"
    virtual_machine_id    = azurerm_linux_virtual_machine.gwlb-nva.id
    provider              = azurerm.connectivity
    publisher             = "Microsoft.Azure.Extensions"
    type                  = "CustomScript"
    type_handler_version  = "2.0"
    settings = <<SETTINGS
        {
            "script": "${base64encode(data.template_file.settings.rendered)}"
        }
    SETTINGS
}

#// 7. Create Route Table and assign to NVA VM subnet
#// This is required if for example the NVA VNET is connected to vWAN hub and has a 0.0.0.0/0 route via Azure Firewall.
#// Needed in this case to ensure traffic flow symmetry for VXLAN tunnels between the consumer Public Load Balancer, 
#// GWLB, and the NVA VM running the VXLAN VTEPs for the Internal and External tunnels.

resource "azurerm_route_table" "rt-gwlb-nva" {
  name                          = "rt-gwlb-nva"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.rg.name
  provider                      = azurerm.connectivity
  disable_bgp_route_propagation = false
  route {
    name           = "route-nva-azurecloud-direct"
    address_prefix = "AzureCloud"
    next_hop_type  = "Internet"
  }
}

resource "azurerm_subnet_route_table_association" "rt-gwlb-nva-to-nva-subnet" {
  provider                      = azurerm.connectivity
  subnet_id = azurerm_subnet.subnet-gwlb.id
  route_table_id = azurerm_route_table.rt-gwlb-nva.id
}


#// ------------- Consumer ------------------

#// 1. Create Public Load Balancer chained to GWLB 

resource "azurerm_lb" "lb-ingress" {
  name                = "lb-ingress"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  provider = azurerm.connectivity
  sku                 = "Standard"
  frontend_ip_configuration {
    name                 = "frontend-pip-lb-ingress"
    public_ip_address_id = azurerm_public_ip.pip-lb-ingress.id
    gateway_load_balancer_frontend_ip_configuration_id = azurerm_lb.gwlb-azure-ingress.frontend_ip_configuration[0].id
  }
}

resource "azurerm_lb_backend_address_pool" "lb-ingress-backendaddresspool" {
    name                = "lb-ingress-backendaddresspool"
    provider = azurerm.connectivity
    loadbalancer_id     = azurerm_lb.lb-ingress.id
}

resource "azurerm_lb_probe" "lb-ingress-nginx-probe" {
    loadbalancer_id     = azurerm_lb.lb-ingress.id
    name                = "lb-ingress-nginx-probe"
    provider = azurerm.connectivity
    protocol            = "Http"
    port                = 80
    request_path        = "/"
    interval_in_seconds = 5
    number_of_probes    = 2
}

resource "azurerm_lb_rule" "lb-ingress-all" {
    loadbalancer_id                 = azurerm_lb.lb-ingress.id
    name                            = "lb-ingress-http"
    provider = azurerm.connectivity
    protocol                        = "Tcp"
    frontend_port                   = 80
    backend_port                    = 80
    frontend_ip_configuration_name  = "frontend-pip-lb-ingress"
    backend_address_pool_ids        = [azurerm_lb_backend_address_pool.lb-ingress-backendaddresspool.id]
    #disable_outbound_snat           = true
    probe_id                        = azurerm_lb_probe.lb-ingress-nginx-probe.id
}

#// 2. Create nginx VM NIC as test back-end for Public Load Balancer
#// Traffic flow: external client => Public LB IP => GWLB internal VNI => NVA internal VTEP => <NVA packet processing> => NVA external VTEP => GWLB External VNI => Public LB => external client 

resource "azurerm_network_interface" "nginx-vm-nic" {
  name = "nginx-vm-nic"
  location = var.location
  resource_group_name = azurerm_resource_group.rg.name
  provider = azurerm.connectivity
  #enable_accelerated_networking = true
  ip_configuration {
    name = "nva-nic-internal"
    subnet_id = azurerm_subnet.subnet-workload.id
    private_ip_address_allocation = "Dynamic"
  }
}

#// 3. Associate nginx VM NIC with ingress lb BackEnd Pool

resource "azurerm_network_interface_backend_address_pool_association" "nginx-lb" {
  network_interface_id    = azurerm_network_interface.nginx-vm-nic.id
  provider = azurerm.connectivity
  ip_configuration_name   = "nva-nic-internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lb-ingress-backendaddresspool.id
}

# #// 4. Create test VM for back end pool

resource "azurerm_linux_virtual_machine" "nginx-vm" {
  depends_on=[azurerm_network_interface.nginx-vm-nic]
  name = "nginx-vm"
  location = var.location
  resource_group_name = azurerm_resource_group.rg.name
  provider = azurerm.connectivity
  network_interface_ids = [azurerm_network_interface.nginx-vm-nic.id]
  size = var.vm_size
  source_image_reference {
    publisher = var.ubuntu-publisher
    offer = var.ubuntu-offer
    sku = "18.04-LTS"
    version = "latest"
  }
  os_disk {
    name = "nginx-osdisk"
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  computer_name = "nginx-vm"
  admin_username = var.admin_username
  admin_password = var.admin_password
  disable_password_authentication = false
}

#// 5. Configure test VM (nginx.sh)

resource "azurerm_virtual_machine_extension" "nginx-vm" {
    depends_on = [azurerm_network_security_rule.allowin]
    name                = "nginx"
    virtual_machine_id  = azurerm_linux_virtual_machine.nginx-vm.id
    provider = azurerm.connectivity
    publisher           = "Microsoft.Azure.Extensions"
    type                = "CustomScript"
    type_handler_version = "2.0"
    settings = <<SETTINGS
        {
            "script": "${base64encode(file("nginx.sh"))}"
        }
    SETTINGS
}

#// 6. Optionally configure Bastion for conection to NVA / troubleshooting


#// Grab outputs for testing

output "settings" {
  value = data.template_file.settings.rendered
}

output "gwlb_lb_ip" {
  value = azurerm_lb.gwlb-azure-ingress.private_ip_address
}

output "public_lb_ip" {
  value = azurerm_public_ip.pip-lb-ingress.ip_address
}









