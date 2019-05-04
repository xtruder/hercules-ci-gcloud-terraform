# Here we have an example of how a machine can be provisioned with some config
# after boot. This is useful in case one doesn't want to unecessarily destroy
# and create VMs in a pet scenario.

data "google_compute_network" "default" {
  name = "default"
}

resource "google_compute_firewall" "nixos-allow-ssh-and-icmp" {
  name    = "nixos-allow-ssh-and-icmp"
  network = "${data.google_compute_network.default.name}"

  allow {
    protocol = "icmp"
  }

  // Allow SSH access
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_tags = ["nixos"]
}

resource "google_compute_instance" "hercules-ci" {
  name         = "hercules-ci"
  machine_type = "n1-standard-2"
  zone         = "us-central1-a"

  // Bind the firewall rules
  tags = ["nixos"]
  min_cpu_platform = "Intel Haswell"

  boot_disk {
    initialize_params {
      // Start with an image the deployer can SSH into
      image = "${module.nixos_image_custom.self_link}"
      size  = "20"
    }
  }

  network_interface {
    network = "${data.google_compute_network.default.name}"

    // Give it a public IP
    access_config {}
  }

  lifecycle {
    // No need to re-deploy the machine if the image changed
    // NixOS is already immutable
    ignore_changes = ["boot_disk"]
  }
}

module "deploy_nixos" {
  source = "github.com/tweag/terraform-nixos/deploy_nixos"

  // Deploy the given NixOS configuration. In this case it's the same as the
  // original image. So if the configuration is changed later it will be
  // deployed here.
  nixos_config = "${path.module}/hercules-ci.nix"

  target_user = "root"
  target_host = "${google_compute_instance.hercules-ci.network_interface.0.access_config.0.nat_ip}"

  triggers = {
    // Also re-deploy whenever the VM is re-created
    instance_id = "${google_compute_instance.hercules-ci.id}"
  }

  // Pass some secrets. See the terraform-servets-provider to handle secrets
  // in Terraform
  keys = {
    agent-token = "${var.agent-token}"
  }
}
