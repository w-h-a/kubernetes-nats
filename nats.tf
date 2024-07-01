locals {
  nats_labels = { "app" = "nats" }

  nats_ports = {
    "client"    = 4222,
    "cluster"   = 6222,
    "monitor"   = 8222,
    "metrics"   = 7777,
    "leafnodes" = 7422,
    "gateways"  = 7522,
  }
}

resource "kubernetes_stateful_set" "nats" {
  metadata {
    namespace = var.nats_namespace
    name      = "nats"
    labels    = local.nats_labels
  }

  spec {
    replicas     = 3
    service_name = "nats"

    selector {
      match_labels = local.nats_labels
    }

    template {
      metadata {
        labels = local.nats_labels
      }

      spec {
        share_process_namespace          = true
        termination_grace_period_seconds = 60

        container {
          name              = "nats"
          image             = var.nats_image
          image_pull_policy = var.image_pull_policy

          dynamic "port" {
            for_each = local.nats_ports
            content {
              name           = port.key
              container_port = port.value
            }
          }

          readiness_probe {
            http_get {
              path = "/"
              port = lookup(local.nats_ports, "monitor", 8222)
            }
            initial_delay_seconds = 10
            timeout_seconds       = 5
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/nats-config"
          }

          volume_mount {
            name       = "pid"
            mount_path = "/var/run/nats"
          }

          env {
            name = "POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          env {
            name  = "CLUSTER_ADVERTISE"
            value = "$(POD_NAME).nats.$(POD_NAMESPACE).svc"
          }

          command = [
            "nats-server",
            "--jetstream",
            "--config",
            "/etc/nats-config/nats.conf"
          ]

          lifecycle {
            pre_stop {
              exec {
                command = [
                  "/bin/sh", "-c", "/nats-server -sl=ldm=/var/run/nats/nats.pid && /bin/sleep 60"
                ]
              }
            }
          }
        }

        volume {
          name = "config-volume"

          config_map {
            default_mode = "0644"
            name         = kubernetes_config_map.nats_server.metadata.0.name
          }
        }

        volume {
          name = "pid"
          empty_dir {}
        }
      }
    }

    update_strategy {
      type = "RollingUpdate"
    }
  }

  depends_on = [kubernetes_config_map.nats_server]
}

resource "kubernetes_service" "nats_public" {
  metadata {
    namespace = var.nats_namespace
    name      = "nats-public"
    labels    = local.nats_labels
  }

  spec {
    port {
      name        = "client"
      port        = lookup(local.nats_ports, "client", 4222)
      target_port = "client"
    }

    selector = local.nats_labels
  }
}

resource "kubernetes_service" "nats" {
  metadata {
    namespace = var.nats_namespace
    name      = "nats"
    labels    = local.nats_labels
  }

  spec {
    dynamic "port" {
      for_each = local.nats_ports
      content {
        name = port.key
        port = port.value
      }
    }

    cluster_ip = "None"
    selector   = local.nats_labels
  }
}

resource "kubernetes_pod_disruption_budget_v1" "nats" {
  metadata {
    namespace = var.nats_namespace
    name      = "nats"
    labels    = local.nats_labels
  }

  spec {
    max_unavailable = 1

    selector {
      match_labels = local.nats_labels
    }
  }
}

resource "kubernetes_config_map" "nats_server" {
  metadata {
    namespace = var.nats_namespace
    name      = "nats-config"
    labels    = local.nats_labels
  }

  data = {
    "nats.conf" = <<-NATSCONF
      server_name: nats-server 
      pid_file: "/var/run/nats/nats.pid"
      http: 8222
      cluster {
        name: nats-cluster
        port: 6222
        routes [
          nats://nats-0.nats.${var.nats_namespace}.svc:6222
          nats://nats-1.nats.${var.nats_namespace}.svc:6222
          nats://nats-2.nats.${var.nats_namespace}.svc:6222
        ]
        cluster_advertise: $CLUSTER_ADVERTISE
        connect_retries: 30
      }
      jetstream {
        max_memory_store: 1Gb
        max_file_store: 1Gb
      }
    NATSCONF
  }
}
