
resource "tls_private_key" "ansible_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ansible_pem" {
    content     = "${tls_private_key.ansible_key.private_key_pem}"
    filename = "${path.module}/ansible.pem"
}

resource "null_resource" "ansible_pem_permission" {
  depends_on = ["local_file.ansible_pem"]
  provisioner "local-exec" {
    command = "chmod 600 ${path.module}/ansible.pem"
  }
}


resource "null_resource" "ansible_host_provision" {
  count = 1
  depends_on = ["azurerm_virtual_machine.master-vm"]

  connection {
    type     = "ssh"
    host = "${azurerm_public_ip.master-lb-publicip.ip_address}"
    port = "2221"
    user = "${var.admin_username}"
    private_key = "${tls_private_key.ansible_key.private_key_pem}"
  }

  provisioner "file" {
    content = "${tls_private_key.ansible_key.private_key_pem}"
    destination = "/home/${var.admin_username}/.ssh/id_rsa"
  }

# install kubespary 's requried pkgs and clone code from github
  provisioner "remote-exec" {
    inline = [ 
      "chmod 600 /home/${var.admin_username}/.ssh/id_rsa",
      "sudo rpm -ivh http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm", 
      "sudo yum install  -y git python-pip", 
      "git clone https://github.com/sorididim11/kubespray.git", 
      "sudo pip install  -r  /home/${var.admin_username}/kubespray/requirements.txt"
    ]
  }

# copy vault file for redhat subscription to ansible host, master[0]
  provisioner "file" {
    source      = "../../password"
    destination = "/home/${var.admin_username}/kubespray/password"
  }
}

resource "local_file" "ansible_inventory" {
  depends_on = ["azurerm_virtual_machine.master-vm", "azurerm_virtual_machine.node-vm", "null_resource.ansible_host_provision"]
  filename = "../../../inventory/azure/hosts"
  content =  <<EOF
${join("\n", formatlist("%s ansible_host=%s ip=%s", azurerm_virtual_machine.master-vm.*.name , azurerm_network_interface.master-nic.*.private_ip_address, azurerm_network_interface.master-nic.*.private_ip_address))}
${join("\n", formatlist("%s ansible_host=%s ip=%s", azurerm_virtual_machine.node-vm.*.name, azurerm_network_interface.slave-nic.*.private_ip_address, azurerm_network_interface.slave-nic.*.private_ip_address ))}

[kube-master]
${join("\n",azurerm_virtual_machine.master-vm.*.name )}

[etcd]
${join("\n",azurerm_virtual_machine.master-vm.*.name)}

[kube-node]
${join("\n",azurerm_virtual_machine.node-vm.*.name)}
  
[k8s-cluster:children]
kube-master
kube-node

[kube-ingress]
${azurerm_virtual_machine.node-vm.0.name}
EOF
}


resource "null_resource" "k8s_build_cluster" {
  count = 1
  depends_on = ["local_file.ansible_inventory"]
  triggers = {
    content = "${local_file.ansible_inventory.content}"
  }
  connection {
      user = "${var.admin_username}"
      host = "${azurerm_public_ip.master-lb-publicip.ip_address}"
      port =  "2221"
      private_key = "${tls_private_key.ansible_key.private_key_pem}"
  }
# copy host file to ansible host, master[0]
  provisioner "file" {
    source      = "${var.ansible_inventory_home}/hosts"
    destination = "/home/${var.admin_username}/kubespray/inventory/azure/hosts"
  }

# copy private key to master[0] for ansible
  provisioner "remote-exec" {
    inline = [ "ANSIBLE_CONFIG=kubespray/inventory/azure/ansible.cfg ansible-playbook --vault-password-file=kubespray/password kubespray/customized/site.yml --become --extra-vars 'azure_subscription_id=${var.subscription_id} azure_tenant_id=${var.tenant_id} azure_aad_client_id=${var.client_id} azure_aad_client_secret=${var.client_secret} azure_location=${var.location}'"]
  }
}


resource "null_resource" "clean-up-redhat-licenses" {
  depends_on = ["azurerm_virtual_machine.master-vm", "azurerm_virtual_machine.node-vm"]
  connection {
    user = "${var.admin_username}"
    host = "${azurerm_public_ip.master-lb-publicip.ip_address}"
    port =  "2221"
    private_key = "${tls_private_key.ansible_key.private_key_pem}"
  }

  provisioner "remote-exec" {
    when    = "destroy"
    inline = ["ANSIBLE_CONFIG=kubespray/inventory/azure/ansible.cfg ansible-playbook --vault-password-file=kubespray/password kubespray/customized/util-redhat-subscription.yml --become --extra-vars is_register=false -vvv"]
  }
}