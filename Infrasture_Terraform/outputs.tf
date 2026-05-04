output "load_balancer_ip" {
  value = google_compute_global_address.lb_ip.address
}

output "ssl_certificate_status" {
  value = google_compute_managed_ssl_certificate.main.managed[0].status
}

output "app_url" {
  value = "https://${var.domains[0]}"
}

output "region_us_mig" {
  value = module.region_us.instance_group
}

output "region_eu_mig" {
  value = module.region_eu.instance_group
}

output "region_asia_mig" {
  value = module.region_asia.instance_group
}

output "backend_service_id" {
  value = google_compute_backend_service.main.id
}

output "cloud_armor_policy" {
  value = google_compute_security_policy.waf.name
}

output "network_id" {
  value = google_compute_network.main.id
}

output "dns_instructions" {
  value = <<-EOT
    ============================================================
    DNS CONFIGURATION REQUIRED
    ============================================================
    Create an A record in your DNS provider:

      ${var.domains[0]}  →  ${google_compute_global_address.lb_ip.address}

    SSL certificate provisioning takes 10–60 minutes after DNS
    propagates. Check status with:
      terraform output ssl_certificate_status
    ============================================================
  EOT
}