variable "nats_namespace" {
  description = "The namespace of the nats broker"
  type        = string
}

variable "nats_image" {
  description = "The nats-io image"
  default     = "nats:v2.10.16"
}

variable "image_pull_policy" {
  description = "K8s image pull policy"
  type        = string
}
