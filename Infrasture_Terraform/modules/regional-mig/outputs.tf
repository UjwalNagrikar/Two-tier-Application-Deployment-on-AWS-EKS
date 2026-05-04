output "instance_group" {
  value = google_compute_region_instance_group_manager.app.instance_group
}

output "mig_id" {
  value = google_compute_region_instance_group_manager.app.id
}

output "subnet_id" {
  value = google_compute_subnetwork.regional.id
}

output "nat_ip" {
  value = google_compute_router_nat.nat.name
}

output "service_account_email" {
  value = google_service_account.instance_sa.email
}