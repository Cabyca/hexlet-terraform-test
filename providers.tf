terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}


variable "yc_token" {}
variable "yc_postgresql_version" {}
variable "db_user" {}
variable "db_password" {}
variable "db_name" {}
variable "yc_folder_id" {}

provider "yandex" {
  token = var.yc_token
  folder_id = var.yc_folder_id
  zone  = "ru-central1-a"
}

resource "yandex_vpc_network" "net" {
  name = "tfhexlet"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "tfhexlet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["192.168.192.0/24"]
}

# Балансировщик нагрузки

# создание целевой группы

resource "yandex_lb_target_group" "foo" {
  name      = "my-target-group"
  folder_id = var.yc_folder_id

  target {
    subnet_id = "${yandex_vpc_subnet.subnet.id}"
    address   = "${yandex_compute_instance.vm.network_interface.0.ip_address}"
  }

  target {
    subnet_id = "${yandex_vpc_subnet.subnet.id}"
    address   = "${yandex_compute_instance.vm2.network_interface.0.ip_address}"
  }
}

resource "yandex_lb_network_load_balancer" "balancer" {
  name = "my-network-load-balancer"

  listener {
    name = "my-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = "${yandex_lb_target_group.foo.id}"

    healthcheck {
      name = "http"
      http_options {
        port = 80
      }
    }
  }
}

data "yandex_compute_image" "img" {
  family = "container-optimized-image"
}

resource "yandex_mdb_postgresql_cluster" "dbcluster" {
  name        = "tfhexlet"
  environment = "PRESTABLE"
  network_id  = yandex_vpc_network.net.id
  depends_on  = [yandex_vpc_network.net, yandex_vpc_subnet.subnet]

  config {
    version = var.yc_postgresql_version
    resources {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-ssd"
      disk_size          = 15
    }
    postgresql_config = {
      max_connections = 100
    }
  }

  maintenance_window {
    type = "WEEKLY"
    day  = "SAT"
    hour = 12
  }

  host {
    zone      = "ru-central1-a"
    subnet_id = yandex_vpc_subnet.subnet.id
  }
}

resource "yandex_mdb_postgresql_user" "dbuser" {
  cluster_id = yandex_mdb_postgresql_cluster.dbcluster.id
  name       = var.db_user
  password   = var.db_password
  depends_on = [yandex_mdb_postgresql_cluster.dbcluster]
}

resource "yandex_mdb_postgresql_database" "db" {
  cluster_id = yandex_mdb_postgresql_cluster.dbcluster.id
  name       = var.db_name
  owner      = yandex_mdb_postgresql_user.dbuser.name
  lc_collate = "en_US.UTF-8"
  lc_type    = "en_US.UTF-8"
  depends_on = [yandex_mdb_postgresql_cluster.dbcluster]
}

resource "yandex_compute_instance" "vm" {
  name = "tfhexlet"
  zone = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.img.id
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_ed25519")
    host        = self.network_interface[0].nat_ip_address
  }

  provisioner "remote-exec" {
    inline = [
      <<EOT
sudo docker run -d -p 0.0.0.0:80:3000 \
  -e DB_TYPE=postgres \
  -e DB_NAME=${var.db_name} \
  -e DB_HOST=${yandex_mdb_postgresql_cluster.dbcluster.host.0.fqdn} \
  -e DB_PORT=6432 \
  -e DB_USER=${var.db_user} \
  -e DB_PASS=${var.db_password} \
  ghcr.io/requarks/wiki:2.5
EOT
    ]
  }
  depends_on = [yandex_mdb_postgresql_cluster.dbcluster]
}


resource "yandex_compute_instance" "vm2" {
  name = "tfhexlet2"
  zone = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.img.id
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_ed25519")
    host        = self.network_interface[0].nat_ip_address
  }

  provisioner "remote-exec" {
    inline = [
      <<EOT
sudo docker run -d -p 0.0.0.0:80:3000 \
  -e DB_TYPE=postgres \
  -e DB_NAME=${var.db_name} \
  -e DB_HOST=${yandex_mdb_postgresql_cluster.dbcluster.host.0.fqdn} \
  -e DB_PORT=6432 \
  -e DB_USER=${var.db_user} \
  -e DB_PASS=${var.db_password} \
  ghcr.io/requarks/wiki:2.5
EOT
    ]
  }
  depends_on = [yandex_mdb_postgresql_cluster.dbcluster]
}
