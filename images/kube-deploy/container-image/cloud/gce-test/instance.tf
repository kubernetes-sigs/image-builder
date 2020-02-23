provider "google" {
  region  = "us-central1"
  project = var.google_project
}

variable "google_project" {
  type = string
}

variable "image_name" {
  type    = string
  default = "buster-gce"
}

data "google_project" "project" {
}


resource "google_compute_instance" "test" {
  name         = "test-${var.image_name}"
  machine_type = "e2-medium"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = data.google_compute_image.default.self_link
      size  = 40
    }
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral IP
    }
  }

  tags = ["imagebuilder-test"]
}

resource "google_compute_firewall" "default" {
  name    = "imagebuilder-test-allow-ssh"
  network = google_compute_instance.test.network_interface.0.network

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = ["imagebuilder-test"]
}


data "google_compute_image" "default" {
  family = var.image_name
}


# Output the instance IP
output "test_instance_name" {
  value = google_compute_instance.test.name
}
output "test_instance_zone" {
  value = google_compute_instance.test.zone
}
output "test_instance_public_ip" {
  value = google_compute_instance.test.network_interface.0.access_config.0.nat_ip
}
