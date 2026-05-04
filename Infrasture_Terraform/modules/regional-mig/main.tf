resource "google_compute_subnetwork" "regional" {
  name          = "${var.app_name}-subnet-${var.region}"
  region        = var.region
  network       = var.network_self_link
  ip_cidr_range = var.subnet_cidr

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_router" "nat_router" {
  name    = "${var.app_name}-router-${var.region}"
  region  = var.region
  network = var.network_self_link
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.app_name}-nat-${var.region}"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_service_account" "instance_sa" {
  account_id   = "${var.app_name}-sa-${substr(var.region, 0, 6)}"
  display_name = "${var.app_name} instance SA (${var.region})"
  project      = var.project_id
}

resource "google_project_iam_member" "sa_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.instance_sa.email}"
}

resource "google_project_iam_member" "sa_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.instance_sa.email}"
}

resource "google_project_iam_member" "sa_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.instance_sa.email}"
}

locals {
  startup_script = <<-STARTUP
    #!/bin/bash
    set -euxo pipefail

    if ! command -v docker &>/dev/null; then
      apt-get update -y
      apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) \
        signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
      apt-get update -y
      apt-get install -y docker-ce docker-ce-cli containerd.io
      systemctl enable --now docker
    fi

    gcloud auth configure-docker us-central1-docker.pkg.dev --quiet 2>/dev/null || true
    gcloud auth configure-docker europe-west1-docker.pkg.dev --quiet 2>/dev/null || true
    gcloud auth configure-docker asia-southeast1-docker.pkg.dev --quiet 2>/dev/null || true

    docker pull ${var.docker_image}

    docker stop ${var.app_name} 2>/dev/null || true
    docker rm   ${var.app_name} 2>/dev/null || true

    docker run -d \
      --name ${var.app_name} \
      --restart unless-stopped \
      -p ${var.app_port}:80 \
      --log-driver=gcplogs \
      --log-opt gcp-project=${var.project_id} \
      --log-opt labels=region,app \
      --label region=${var.region} \
      --label app=${var.app_name} \
      ${var.docker_image}

    echo "Container started successfully in region ${var.region}"
  STARTUP
}

resource "google_compute_instance_template" "app" {
  name_prefix  = "${var.app_name}-tmpl-${var.region}-"
  machine_type = var.machine_type
  region       = var.region
  tags         = ["${var.app_name}-server"]
  labels       = merge(var.labels, { region = var.region })

  lifecycle {
    create_before_destroy = true
  }

  metadata = {
    startup-script = local.startup_script
    enable-oslogin = "TRUE"
  }

  disk {
    auto_delete  = true
    boot         = true
    source_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    disk_size_gb = 20
    disk_type    = "pd-balanced"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.regional.self_link
  }

  service_account {
    email  = google_service_account.instance_sa.email
    scopes = ["cloud-platform"]
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

resource "google_compute_region_instance_group_manager" "app" {
  name               = "${var.app_name}-mig-${var.region}"
  region             = var.region
  base_instance_name = "${var.app_name}-${var.region}"
  target_size        = null

  version {
    instance_template = google_compute_instance_template.app.id
    name              = "primary"
  }

  named_port {
    name = "http"
    port = var.app_port
  }

  update_policy {
    type                         = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = 2
    max_unavailable_fixed        = 0
    replacement_method           = "SUBSTITUTE"
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.regional.id
    initial_delay_sec = 120
  }

  depends_on = [google_compute_router_nat.nat]
}

resource "google_compute_health_check" "regional" {
  name               = "${var.app_name}-hc-${var.region}"
  check_interval_sec = 10
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = var.app_port
    request_path = "/"
  }
}

resource "google_compute_region_autoscaler" "app" {
  name   = "${var.app_name}-as-${var.region}"
  region = var.region
  target = google_compute_region_instance_group_manager.app.id

  autoscaling_policy {
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas
    cooldown_period = 90

    cpu_utilization {
      target = 0.70
    }

    load_balancing_utilization {
      target = 0.80
    }
  }
}