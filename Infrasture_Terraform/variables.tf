variable "project_id" {
  type = string
}

variable "primary_region" {
  type    = string
  default = "us-central1"
}

variable "app_name" {
  type    = string
  default = "devsecops"
}

variable "environment" {
  type    = string
  default = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "docker_image" {
  type = string
}

variable "app_port" {
  type    = number
  default = 80
}

variable "health_check_path" {
  type    = string
  default = "/"
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}

variable "min_replicas" {
  type    = number
  default = 1
}

variable "max_replicas" {
  type    = number
  default = 5
}

variable "domains" {
  type    = list(string)
  default = ["example.com", "www.example.com"]
}

variable "ssh_allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "common_labels" {
  type = map(string)
  default = {
    project    = "devsecops-platform"
    managed_by = "terraform"
    owner      = "ujwal-nagrikar"
  }
}