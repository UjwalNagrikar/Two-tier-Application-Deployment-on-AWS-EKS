terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.primary_region
}

provider "google-beta" {
  project = var.project_id
  region  = var.primary_region
}

resource "google_compute_network" "main" {
  name                    = "${var.app_name}-vpc"
  auto_create_subnetworks = false
  description             = "Global VPC for ${var.app_name} multi-region deployment"
}

module "region_us" {
  source = "./modules/regional-mig"

  project_id        = var.project_id
  app_name          = var.app_name
  region            = "us-central1"
  zone              = "us-central1-a"
  subnet_cidr       = "10.10.0.0/20"
  network_self_link = google_compute_network.main.self_link
  docker_image      = var.docker_image
  app_port          = var.app_port
  min_replicas      = var.min_replicas
  max_replicas      = var.max_replicas
  machine_type      = var.machine_type
  environment       = var.environment
  labels            = var.common_labels
}

module "region_eu" {
  source = "./modules/regional-mig"

  project_id        = var.project_id
  app_name          = var.app_name
  region            = "europe-west1"
  zone              = "europe-west1-b"
  subnet_cidr       = "10.20.0.0/20"
  network_self_link = google_compute_network.main.self_link
  docker_image      = var.docker_image
  app_port          = var.app_port
  min_replicas      = var.min_replicas
  max_replicas      = var.max_replicas
  machine_type      = var.machine_type
  environment       = var.environment
  labels            = var.common_labels
}

module "region_asia" {
  source = "./modules/regional-mig"

  project_id        = var.project_id
  app_name          = var.app_name
  region            = "asia-southeast1"
  zone              = "asia-southeast1-a"
  subnet_cidr       = "10.30.0.0/20"
  network_self_link = google_compute_network.main.self_link
  docker_image      = var.docker_image
  app_port          = var.app_port
  min_replicas      = var.min_replicas
  max_replicas      = var.max_replicas
  machine_type      = var.machine_type
  environment       = var.environment
  labels            = var.common_labels
}

resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.app_name}-allow-health-check"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = [tostring(var.app_port)]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["${var.app_name}-server"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.app_name}-allow-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_allowed_cidrs
  target_tags   = ["${var.app_name}-server"]
}

resource "google_compute_firewall" "allow_app" {
  name    = "${var.app_name}-allow-app"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = [tostring(var.app_port), "443", "80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.app_name}-server"]
}

resource "google_compute_global_address" "lb_ip" {
  name        = "${var.app_name}-global-ip"
  description = "Global anycast IP for ${var.app_name} load balancer"
}

resource "google_compute_health_check" "global_http" {
  name               = "${var.app_name}-global-hc"
  check_interval_sec = 10
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = var.app_port
    request_path = var.health_check_path
  }
}

resource "google_compute_backend_service" "main" {
  name                  = "${var.app_name}-backend-svc"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.global_http.id]

  backend {
    group           = module.region_us.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
    max_utilization = 0.8
    description     = "US Central backend"
  }

  backend {
    group           = module.region_eu.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
    max_utilization = 0.8
    description     = "Europe West backend"
  }

  backend {
    group           = module.region_asia.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
    max_utilization = 0.8
    description     = "Asia Southeast backend"
  }

  security_policy = google_compute_security_policy.waf.id

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_url_map" "main" {
  name            = "${var.app_name}-url-map"
  default_service = google_compute_backend_service.main.id
}

resource "google_compute_url_map" "http_redirect" {
  name = "${var.app_name}-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  name    = "${var.app_name}-http-proxy"
  url_map = google_compute_url_map.http_redirect.id
}

resource "google_compute_target_https_proxy" "main" {
  name             = "${var.app_name}-https-proxy"
  url_map          = google_compute_url_map.main.id
  ssl_certificates = [google_compute_managed_ssl_certificate.main.id]
}

resource "google_compute_managed_ssl_certificate" "main" {
  name = "${var.app_name}-ssl-cert"

  managed {
    domains = var.domains
  }
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.app_name}-http-fwd"
  target                = google_compute_target_http_proxy.redirect.id
  port_range            = "80"
  ip_address            = google_compute_global_address.lb_ip.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_global_forwarding_rule" "https" {
  name                  = "${var.app_name}-https-fwd"
  target                = google_compute_target_https_proxy.main.id
  port_range            = "443"
  ip_address            = google_compute_global_address.lb_ip.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_security_policy" "waf" {
  name        = "${var.app_name}-waf-policy"
  description = "Cloud Armor WAF for DevSecOps platform"

  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-v33-stable')"
      }
    }
    description = "Block XSS attacks"
  }

  rule {
    action   = "deny(403)"
    priority = 1001
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable')"
      }
    }
    description = "Block SQL injection"
  }

  rule {
    action   = "deny(403)"
    priority = 1002
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-v33-stable')"
      }
    }
    description = "Block local file inclusion"
  }

  rule {
    action   = "throttle"
    priority = 2000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 1000
        interval_sec = 60
      }
    }
    description = "Rate limiting per source IP"
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }
}