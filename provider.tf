terraform {
  required_version = ">= 1.5.2"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29.0"
    }
  }
}
