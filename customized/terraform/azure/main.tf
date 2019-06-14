provider "azurerm" {
	subscription_id = "${var.subscription_id}"
	client_id       = "${var.client_id}"
	client_secret   = "${var.client_secret}"
    tenant_id       = "${var.tenant_id}"
}



resource "azurerm_resource_group" "cluster-group" {
	name = "${var.resource_group_name}"
	location = "${var.location}"
}


resource "random_id" "random-id" {
	keepers = {
		resource_group = "${azurerm_resource_group.cluster-group.name}"	
	}
	byte_length = 8
}


resource "azurerm_route_table" "routetable" {
  name                = "${var.resource_name_prefix}-routetable"
  resource_group_name = "${azurerm_resource_group.cluster-group.name}"
  location            = "${var.location}"
}


resource "azurerm_virtual_network" "vnet" {
	name = "${var.resource_name_prefix}-net"
	address_space = ["${var.vnet_cidr}"]
	location = "${var.location}"
	resource_group_name = "${azurerm_resource_group.cluster-group.name}"
}

