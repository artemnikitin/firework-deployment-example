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

  # Effective secret values — directly from Terraform resources when auto-generated,
  # from Secret Manager data sources when operator-provided.
  secret_events_tls_cert    = local.auto_generate_tls_material ? tls_locally_signed_cert.auto_events_tls[0].cert_pem : data.google_secret_manager_secret_version.user_events_tls_cert[0].secret_data
  secret_events_tls_key     = local.auto_generate_tls_material ? tls_private_key.auto_events_tls[0].private_key_pem : data.google_secret_manager_secret_version.user_events_tls_key[0].secret_data
  secret_registry_tls_cert  = local.auto_generate_tls_material ? tls_locally_signed_cert.auto_registry_tls[0].cert_pem : data.google_secret_manager_secret_version.user_registry_tls_cert[0].secret_data
  secret_registry_tls_key   = local.auto_generate_tls_material ? tls_private_key.auto_registry_tls[0].private_key_pem : data.google_secret_manager_secret_version.user_registry_tls_key[0].secret_data
  secret_enrollment_ca_cert = local.auto_generate_tls_material ? tls_self_signed_cert.auto_root_ca[0].cert_pem : data.google_secret_manager_secret_version.user_enrollment_ca_cert[0].secret_data
  secret_enrollment_ca_key  = local.auto_generate_tls_material ? tls_private_key.auto_root_ca[0].private_key_pem : data.google_secret_manager_secret_version.user_enrollment_ca_key[0].secret_data
  secret_bootstrap_token    = local.auto_generate_bootstrap ? random_password.auto_bootstrap_token[0].result : data.google_secret_manager_secret_version.user_bootstrap_token[0].secret_data
}

# ---------------------------------------------------------------------------
# Secret Manager data sources — only for operator-provided secrets
# ---------------------------------------------------------------------------

data "google_secret_manager_secret_version" "webhook_secret" {
  secret  = var.webhook_secret_id
  version = "latest"
}

data "google_secret_manager_secret_version" "user_events_tls_cert" {
  count   = !local.auto_generate_tls_material ? 1 : 0
  secret  = var.events_tls_cert_secret_id
  version = "latest"
}

data "google_secret_manager_secret_version" "user_events_tls_key" {
  count   = !local.auto_generate_tls_material ? 1 : 0
  secret  = var.events_tls_key_secret_id
  version = "latest"
}

data "google_secret_manager_secret_version" "user_registry_tls_cert" {
  count   = !local.auto_generate_tls_material ? 1 : 0
  secret  = var.registry_tls_cert_secret_id
  version = "latest"
}

data "google_secret_manager_secret_version" "user_registry_tls_key" {
  count   = !local.auto_generate_tls_material ? 1 : 0
  secret  = var.registry_tls_key_secret_id
  version = "latest"
}

data "google_secret_manager_secret_version" "user_enrollment_ca_cert" {
  count   = !local.auto_generate_tls_material ? 1 : 0
  secret  = var.enrollment_ca_cert_secret_id
  version = "latest"
}

data "google_secret_manager_secret_version" "user_enrollment_ca_key" {
  count   = !local.auto_generate_tls_material ? 1 : 0
  secret  = var.enrollment_ca_key_secret_id
  version = "latest"
}

data "google_secret_manager_secret_version" "user_bootstrap_token" {
  count   = !local.auto_generate_bootstrap ? 1 : 0
  secret  = var.bootstrap_token_secret_id
  version = "latest"
}

data "google_secret_manager_secret_version" "github_token" {
  count   = var.github_token_secret_id != "" ? 1 : 0
  secret  = var.github_token_secret_id
  version = "latest"
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
# Kubernetes Secrets — secret values written at apply time, mounted as files.
# Keys use dashes; items{} maps them to the paths the app expects.
# ---------------------------------------------------------------------------

resource "kubernetes_secret" "events_secrets" {
  metadata {
    name      = "firework-events-secrets"
    namespace = kubernetes_namespace.firework.metadata[0].name
  }
  data = {
    "webhook-secret" = data.google_secret_manager_secret_version.webhook_secret.secret_data
    "tls-server-crt" = local.secret_events_tls_cert
    "tls-server-key" = local.secret_events_tls_key
  }
}

resource "kubernetes_secret" "registry_secrets" {
  metadata {
    name      = "firework-registry-secrets"
    namespace = kubernetes_namespace.firework.metadata[0].name
  }
  data = {
    "bootstrap-token"   = local.secret_bootstrap_token
    "tls-server-crt"    = local.secret_registry_tls_cert
    "tls-server-key"    = local.secret_registry_tls_key
    "enrollment-ca-crt" = local.secret_enrollment_ca_cert
    "enrollment-ca-key" = local.secret_enrollment_ca_key
  }
}

resource "kubernetes_secret" "controller_secrets" {
  metadata {
    name      = "firework-controller-secrets"
    namespace = kubernetes_namespace.firework.metadata[0].name
  }
  data = {
    "bootstrap-token" = local.secret_bootstrap_token
  }
}

resource "kubernetes_secret" "github_token" {
  count = var.github_token_secret_id != "" ? 1 : 0
  metadata {
    name      = "firework-github-token"
    namespace = kubernetes_namespace.firework.metadata[0].name
  }
  data = {
    token = data.google_secret_manager_secret_version.github_token[0].secret_data
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
          secret {
            secret_name  = kubernetes_secret.events_secrets.metadata[0].name
            default_mode = "0444"
            items {
              key  = "webhook-secret"
              path = "secrets/webhook-secret"
            }
            items {
              key  = "tls-server-crt"
              path = "tls/server.crt"
            }
            items {
              key  = "tls-server-key"
              path = "tls/server.key"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.controlplane_accessor,
    google_storage_bucket_iam_member.state_object_admin,
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
          secret {
            secret_name  = kubernetes_secret.registry_secrets.metadata[0].name
            default_mode = "0444"
            items {
              key  = "bootstrap-token"
              path = "secrets/bootstrap-token"
            }
            items {
              key  = "tls-server-crt"
              path = "tls/server.crt"
            }
            items {
              key  = "tls-server-key"
              path = "tls/server.key"
            }
            items {
              key  = "enrollment-ca-crt"
              path = "tls/enrollment-ca.crt"
            }
            items {
              key  = "enrollment-ca-key"
              path = "tls/enrollment-ca.key"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.controlplane_accessor,
    google_storage_bucket_iam_member.state_object_admin,
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
          secret {
            secret_name  = kubernetes_secret.controller_secrets.metadata[0].name
            default_mode = "0444"
            items {
              key  = "bootstrap-token"
              path = "secrets/bootstrap-token"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_storage_bucket_iam_member.state_object_admin,
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
