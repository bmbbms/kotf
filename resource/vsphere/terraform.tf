provider "vsphere" {
  user = "{{ vc_username }}"
  password = "{{ vc_password }}"
  vsphere_server = "{{ vc_host }}"

  # If you have a self-signed cert
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
  name = "{{ region }}"
}

{% for zone in zones %}
data "vsphere_resource_pool" "{{ zone.key }}" {
  {% if zone.name=='Resources' %}
   name          = "{{zone.vc_cluster}}/Resources"
  {% endif %}
  {% if zone.name!='Resources' %}
   name          = "{{zone.vc_cluster}}/Resources/{{ zone.name }}"
  {% endif %}
   datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_network" "{{ zone.key }}" {
  name = "{{ zone.vc_network }}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_datastore" "{{zone.key}}" {
  name = "{{ zone.vc_storage }}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

{% if zone.template_type == undefined or zone.template_type == 'default'%}
data "vsphere_virtual_machine" "template" {
  name = "kubeoperator/{{ image_name }}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}
{% endif %}

{% if zone.template_type != undefined and  zone.template_type == 'customize'%}
data "vsphere_virtual_machine" "template" {
  name = "{{ zone.image_name }}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}
{% endif %}

{% endfor %}

{% for host in hosts %}
resource "vsphere_virtual_machine" "{{host.short_name}}" {
  name = "{{ host.name }}"
  folder = "kubeoperator"
  resource_pool_id = "${data.vsphere_resource_pool.{{host.zone.key}}.id}"
  datastore_id = "${data.vsphere_datastore.{{host.zone.key}}.id}"
  num_cpus = {{ host.cpu }}
  memory = {{ host.memory }}
  {% if host.guest_id == undefined %}
  guest_id = "otherLinux64Guest"
  {% endif %}

  {% if host.guest_id != undefined %}
  guest_id = "{{ host.guest_id }}"
  {% endif %}

  network_interface {
    network_id = "${data.vsphere_network.{{host.zone.key}}.id}"
  }

  disk {
    label            = "disk0"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  lifecycle {
    ignore_changes = [
      disk,
    ]
  }


  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"
    timeout = 60
    customize {

      linux_options {
        host_name = "{{ host.short_name }}"
        domain = "{{ host.domain }}"
      }

      network_interface {
        ipv4_address = "{{ host.ip }}"
        ipv4_netmask = "{{host.zone.net_mask}}"
      }
      ipv4_gateway = "{{host.zone.vc_gateway}}"
    }
  }
}
{% endfor %}