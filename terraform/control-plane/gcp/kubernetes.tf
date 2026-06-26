locals {
  k8s_namespace = "firework"
  k8s_sa_name   = "firework-controlplane"
  secrets_mount = "/etc/firework"
  config_mount  = "/etc/firework-config"
  config_file   = "/etc/firework-config/controlplane.yaml"

  events_config = yamlencode({
    role               = "events"
    events_listen_addr = var.events_listen_addr
    state = {
      backend = "gcs"
      prefix  = var.state_prefix
      gcs = {
        bucket  = google_storage_bucket.state.name
        project = var.gcp_project
      }
    }
    leader_lease_ttl           = var.leader_lease_ttl
    leader_renew_interval      = var.leader_renew_interval
    node_stale_ttl             = var.node_stale_ttl
    controller_tick            = var.controller_tick
    target_branch              = var.target_branch
    config_dir                 = var.config_dir
    git_repo_url               = var.git_repo_url
    reconcile_on_start         = var.reconcile_on_start
    github_webhook_secret_file = "${local.secrets_mount}/secrets/webhook-secret"
    tls = {
      cert_file = "${local.secrets_mount}/tls/server.crt"
      key_file  = "${local.secrets_mount}/tls/server.key"
    }
  })

  registry_config = yamlencode({
    role                 = "registry"
    registry_listen_addr = var.registry_listen_addr
    state = {
      backend = "gcs"
      prefix  = var.state_prefix
      gcs = {
        bucket  = google_storage_bucket.state.name
        project = var.gcp_project
      }
    }
    leader_lease_ttl      = var.leader_lease_ttl
    leader_renew_interval = var.leader_renew_interval
    node_stale_ttl        = var.node_stale_ttl
    controller_tick       = var.controller_tick
    tls = {
      cert_file      = "${local.secrets_mount}/tls/server.crt"
      key_file       = "${local.secrets_mount}/tls/server.key"
      client_ca_file = "${local.secrets_mount}/tls/enrollment-ca.crt"
    }
    enrollment = {
      ca_file       = "${local.secrets_mount}/tls/enrollment-ca.crt"
      ca_key_file   = "${local.secrets_mount}/tls/enrollment-ca.key"
      node_cert_ttl = var.registry_node_cert_ttl
      bootstrap_tokens = [{
        token_file = "${local.secrets_mount}/secrets/bootstrap-token"
      }]
    }
  })

  controller_config = yamlencode({
    role = "controller"
    state = {
      backend = "gcs"
      prefix  = var.state_prefix
      gcs = {
        bucket  = google_storage_bucket.state.name
        project = var.gcp_project
      }
    }
    leader_lease_ttl      = var.leader_lease_ttl
    leader_renew_interval = var.leader_renew_interval
    node_stale_ttl        = var.node_stale_ttl
    controller_tick       = var.controller_tick
  })

  # CSI secrets YAML for each role's SecretProviderClass
  events_csi_secrets = <<-EOT
    - resourceName: "projects/${var.gcp_project}/secrets/${var.webhook_secret_id}/versions/latest"
      path: "secrets/webhook-secret"
    - resourceName: "projects/${var.gcp_project}/secrets/${var.events_tls_cert_secret_id}/versions/latest"
      path: "tls/server.crt"
    - resourceName: "projects/${var.gcp_project}/secrets/${var.events_tls_key_secret_id}/versions/latest"
      path: "tls/server.key"
  EOT

  registry_csi_secrets = <<-EOT
    - resourceName: "projects/${var.gcp_project}/secrets/${var.bootstrap_token_secret_id}/versions/latest"
      path: "secrets/bootstrap-token"
    - resourceName: "projects/${var.gcp_project}/secrets/${var.registry_tls_cert_secret_id}/versions/latest"
      path: "tls/server.crt"
    - resourceName: "projects/${var.gcp_project}/secrets/${var.registry_tls_key_secret_id}/versions/latest"
      path: "tls/server.key"
    - resourceName: "projects/${var.gcp_project}/secrets/${var.enrollment_ca_cert_secret_id}/versions/latest"
      path: "tls/enrollment-ca.crt"
    - resourceName: "projects/${var.gcp_project}/secrets/${var.enrollment_ca_key_secret_id}/versions/latest"
      path: "tls/enrollment-ca.key"
  EOT

  controller_csi_secrets = <<-EOT
    - resourceName: "projects/${var.gcp_project}/secrets/${var.bootstrap_token_secret_id}/versions/latest"
      path: "secrets/bootstrap-token"
  EOT
}

# ---------------------------------------------------------------------------
# Namespace and ServiceAccount
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "firework" {
  metadata {
    name   = local.k8s_namespace
    labels = local.common_labels
  }
}

resource "kubernetes_service_account" "controlplane" {
  metadata {
    name      = local.k8s_sa_name
    namespace = kubernetes_namespace.firework.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.controlplane.email
    }
  }
}

# ---------------------------------------------------------------------------
# ConfigMaps (one per role — no secret values)
# ---------------------------------------------------------------------------

resource "kubernetes_config_map" "events" {
  metadata {
    name      = "firework-events-config"
    namespace = kubernetes_namespace.firework.metadata[0].name
  }
  data = {
    "controlplane.yaml" = local.events_config
  }
}

resource "kubernetes_config_map" "registry" {
  metadata {
    name      = "firework-registry-config"
    namespace = kubernetes_namespace.firework.metadata[0].name
  }
  data = {
    "controlplane.yaml" = local.registry_config
  }
}

resource "kubernetes_config_map" "controller" {
  metadata {
    name      = "firework-controller-config"
    namespace = kubernetes_namespace.firework.metadata[0].name
  }
  data = {
    "controlplane.yaml" = local.controller_config
  }
}

# ---------------------------------------------------------------------------
# SecretProviderClasses (GCP Secrets Store CSI driver)
# Files are mounted at local.secrets_mount = /etc/firework
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "spc_events" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "firework-events-secrets"
      namespace = kubernetes_namespace.firework.metadata[0].name
    }
    spec = {
      provider   = "gcp"
      parameters = { secrets = local.events_csi_secrets }
    }
  }
}

# When a GitHub token is provided it is synced to an ephemeral Kubernetes
# Secret via secretObjects so the binary can read it as GITHUB_TOKEN env var.
resource "kubernetes_manifest" "spc_events_github_token" {
  count = var.github_token_secret_id != "" ? 1 : 0

  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "firework-events-github-token"
      namespace = kubernetes_namespace.firework.metadata[0].name
    }
    spec = {
      provider = "gcp"
      parameters = {
        secrets = "- resourceName: \"projects/${var.gcp_project}/secrets/${var.github_token_secret_id}/versions/latest\"\n  path: \"secrets/github-token\"\n"
      }
      secretObjects = [{
        secretName = "firework-github-token"
        type       = "Opaque"
        data = [{
          objectName = "secrets/github-token"
          key        = "token"
        }]
      }]
    }
  }
}

resource "kubernetes_manifest" "spc_registry" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "firework-registry-secrets"
      namespace = kubernetes_namespace.firework.metadata[0].name
    }
    spec = {
      provider   = "gcp"
      parameters = { secrets = local.registry_csi_secrets }
    }
  }
}

resource "kubernetes_manifest" "spc_controller" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "firework-controller-secrets"
      namespace = kubernetes_namespace.firework.metadata[0].name
    }
    spec = {
      provider   = "gcp"
      parameters = { secrets = local.controller_csi_secrets }
    }
  }
}

# ---------------------------------------------------------------------------
# Deployments
# ---------------------------------------------------------------------------

resource "kubernetes_deployment" "events" {
  metadata {
    name      = "firework-events"
    namespace = kubernetes_namespace.firework.metadata[0].name
    labels    = merge(local.common_labels, { role = "events" })
  }
  spec {
    replicas = var.events_replicas
    selector {
      match_labels = { role = "events" }
    }
    template {
      metadata {
        labels = merge(local.common_labels, { role = "events" })
      }
      spec {
        service_account_name = kubernetes_service_account.controlplane.metadata[0].name

        container {
          name  = "controlplane"
          image = var.controlplane_image
          args  = ["--config", local.config_file]

          port {
            name           = "events"
            container_port = 9444
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = local.config_mount
            read_only  = true
          }

          volume_mount {
            name       = "secrets"
            mount_path = local.secrets_mount
            read_only  = true
          }

          dynamic "volume_mount" {
            for_each = var.github_token_secret_id != "" ? [1] : []
            content {
              name       = "github-token"
              mount_path = "/etc/firework-github-token"
              read_only  = true
            }
          }

          dynamic "env" {
            for_each = var.github_token_secret_id != "" ? [1] : []
            content {
              name = "GITHUB_TOKEN"
              value_from {
                secret_key_ref {
                  name     = "firework-github-token"
                  key      = "token"
                  optional = false
                }
              }
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.events.metadata[0].name
          }
        }

        volume {
          name = "secrets"
          csi {
            driver    = "secrets-store.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = "firework-events-secrets"
            }
          }
        }

        dynamic "volume" {
          for_each = var.github_token_secret_id != "" ? [1] : []
          content {
            name = "github-token"
            csi {
              driver    = "secrets-store.csi.k8s.io"
              read_only = true
              volume_attributes = {
                secretProviderClass = "firework-events-github-token"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.controlplane_accessor,
    google_storage_bucket_iam_member.state_object_admin,
    kubernetes_manifest.spc_events,
  ]
}

resource "kubernetes_deployment" "registry" {
  metadata {
    name      = "firework-registry"
    namespace = kubernetes_namespace.firework.metadata[0].name
    labels    = merge(local.common_labels, { role = "registry" })
  }
  spec {
    replicas = var.registry_replicas
    selector {
      match_labels = { role = "registry" }
    }
    template {
      metadata {
        labels = merge(local.common_labels, { role = "registry" })
      }
      spec {
        service_account_name = kubernetes_service_account.controlplane.metadata[0].name

        container {
          name  = "controlplane"
          image = var.controlplane_image
          args  = ["--config", local.config_file]

          port {
            name           = "registry"
            container_port = 9443
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = local.config_mount
            read_only  = true
          }

          volume_mount {
            name       = "secrets"
            mount_path = local.secrets_mount
            read_only  = true
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.registry.metadata[0].name
          }
        }

        volume {
          name = "secrets"
          csi {
            driver    = "secrets-store.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = "firework-registry-secrets"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.controlplane_accessor,
    google_storage_bucket_iam_member.state_object_admin,
    kubernetes_manifest.spc_registry,
  ]
}

resource "kubernetes_deployment" "controller" {
  metadata {
    name      = "firework-controller"
    namespace = kubernetes_namespace.firework.metadata[0].name
    labels    = merge(local.common_labels, { role = "controller" })
  }
  spec {
    replicas = var.controller_replicas
    selector {
      match_labels = { role = "controller" }
    }
    template {
      metadata {
        labels = merge(local.common_labels, { role = "controller" })
      }
      spec {
        service_account_name = kubernetes_service_account.controlplane.metadata[0].name

        container {
          name  = "controlplane"
          image = var.controlplane_image
          args  = ["--config", local.config_file]

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = local.config_mount
            read_only  = true
          }

          volume_mount {
            name       = "secrets"
            mount_path = local.secrets_mount
            read_only  = true
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.controller.metadata[0].name
          }
        }

        volume {
          name = "secrets"
          csi {
            driver    = "secrets-store.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = "firework-controller-secrets"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_storage_bucket_iam_member.state_object_admin,
    kubernetes_manifest.spc_controller,
  ]
}

# ---------------------------------------------------------------------------
# Services (external passthrough NLBs for events and registry)
# ---------------------------------------------------------------------------

resource "kubernetes_service" "events" {
  metadata {
    name      = "firework-events"
    namespace = kubernetes_namespace.firework.metadata[0].name
    labels    = merge(local.common_labels, { role = "events" })
    annotations = {
      "networking.gke.io/load-balancer-type" = "External"
    }
  }
  spec {
    type                        = "LoadBalancer"
    load_balancer_ip            = google_compute_address.events.address
    load_balancer_source_ranges = var.events_allowed_cidrs
    selector                    = { role = "events" }

    port {
      name        = "https"
      port        = 443
      target_port = 9444
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_service" "registry" {
  metadata {
    name      = "firework-registry"
    namespace = kubernetes_namespace.firework.metadata[0].name
    labels    = merge(local.common_labels, { role = "registry" })
    annotations = {
      "networking.gke.io/load-balancer-type" = "External"
    }
  }
  spec {
    type                        = "LoadBalancer"
    load_balancer_ip            = google_compute_address.registry.address
    load_balancer_source_ranges = var.registry_allowed_cidrs
    selector                    = { role = "registry" }

    port {
      name        = "registry"
      port        = 9443
      target_port = 9443
      protocol    = "TCP"
    }
  }
}
