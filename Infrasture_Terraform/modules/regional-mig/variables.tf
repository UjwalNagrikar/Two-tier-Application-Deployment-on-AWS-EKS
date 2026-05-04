variable "project_id" {
  type = string
}

variable "app_name" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "network_self_link" {
  type = string
}

variable "docker_image" {
  type = string
}

variable "app_port" {
  type    = number
  default = 80
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

variable "environment" {
  type    = string
  default = "prod"
}

variable "labels" {
  type    = map(string)
  default = {}
}