data "azurerm_virtual_network" "tfresource" {
  name                = "${var.network}"
  resource_group_name = "${var.networkResourceGroup}"
}

data "azurerm_subnet" "tfresource" {
  name                 = "${var.subnet}"
  resource_group_name  = "${var.networkResourceGroup}"
  virtual_network_name = data.azurerm_virtual_network.tfresource.name
}

locals {
  _isSSHKey = "${var.isPassword ? {} : { empty = true }}"
}

resource "azurerm_resource_group" "tfresource" {
  count = "${var.isNewResourceGroup ? 1 : 0}"
  name = "${var.newResourceGroup}"
  location = "${var.region}"
}

resource "azurerm_public_ip" "tfresource" {
  name                = "${var.vmName}-public-ip"
  resource_group_name = "${var.isNewResourceGroup ? azurerm_resource_group.tfresource[0].name : var.existingResourceGroup}"
  location            = "${var.region}"
  allocation_method   = "Dynamic"
}

resource "azurerm_network_security_group" "security_group" {
  count               = "${var.isAdvancedNetwork ? 0 : 1}"
  name                = "${var.vmName}-security-group"
  location            = "${var.region}"
  resource_group_name = "${var.isNewResourceGroup ? azurerm_resource_group.tfresource[0].name : var.existingResourceGroup}"
}

resource "azurerm_network_security_rule" "ssh_rule" {
  count                       = "${!var.isAdvancedNetwork && var.ssh ? 1 : 0}"
  name                        = "SSH"
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = "${var.isNewResourceGroup ? azurerm_resource_group.tfresource[0].name : var.existingResourceGroup}"
  network_security_group_name = "${azurerm_network_security_group.security_group[0].name}"
}

resource "azurerm_network_security_rule" "http_rule" {
  count                       = "${!var.isAdvancedNetwork && var.http ? 1 : 0}"
  name                        = "HTTP"
  priority                    = 320
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = "${var.isNewResourceGroup ? azurerm_resource_group.tfresource[0].name : var.existingResourceGroup}"
  network_security_group_name = "${azurerm_network_security_group.security_group[0].name}"
}

resource "azurerm_network_security_rule" "https_rule" {
  count                       = "${!var.isAdvancedNetwork && var.https ? 1 : 0}"
  name                        = "HTTPS"
  priority                    = 340
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = "${var.isNewResourceGroup ? azurerm_resource_group.tfresource[0].name : var.existingResourceGroup}"
  network_security_group_name = "${azurerm_network_security_group.security_group[0].name}"
}

data "azurerm_network_security_group" "existing_security_group" {
  count               = "${var.isAdvancedNetwork ? 1 : 0}"
  name                = "${var.nsgName}"
  resource_group_name = "${var.nsgResourceGroup}"
}

resource "azurerm_network_interface" "tfresource" {
  name                = "${var.nic}"
  location            = "${var.region}"
  resource_group_name = "${var.isNewResourceGroup ? azurerm_resource_group.tfresource[0].name : var.existingResourceGroup}"

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.tfresource.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.tfresource.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg_association" {
  network_interface_id		= "${azurerm_network_interface.tfresource.id}"
  network_security_group_id	= "${var.isAdvancedNetwork ? data.azurerm_network_security_group.existing_security_group[0].id : azurerm_network_security_group.security_group[0].id}"
  depends_on = [azurerm_network_interface.tfresource, data.azurerm_network_security_group.existing_security_group, azurerm_network_security_group.security_group]
}

resource "azurerm_virtual_machine" "tfresource" {
  name                = "${var.vmName}"
  resource_group_name = "${var.isNewResourceGroup ? azurerm_resource_group.tfresource[0].name : var.existingResourceGroup}"
  location            = "${var.region}"
  vm_size                = "${var.size}"
  network_interface_ids = [
    azurerm_network_interface.tfresource.id,
  ]

  os_profile {
    computer_name  = "${var.vmName}"
    admin_username = "${var.adminUserName}"
    admin_password = "${var.isPassword ? var.password : null}"
  }
  os_profile_linux_config {
    disable_password_authentication = "${var.isPassword ? false : true}"
    dynamic "ssh_keys" {
      for_each = local._isSSHKey
      content {
        key_data = "${var.publicKey}"
        path = "/home/${var.adminUserName}/.ssh/authorized_keys"
      }
    }
  }

  storage_os_disk {
    name		= "${var.vmName}-os-disk"
    caching              = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
    publisher = "${var.image_publisher}"
    offer     = "${var.image_offer}"
    sku       = "${var.image_sku}"
    version   = "${var.image_version}"
  }

  delete_os_disk_on_termination = "${var.deleteOSDiskOnTerm}"
  depends_on = [azurerm_network_interface_security_group_association.nic_nsg_association]
}
