locals {
  k8s_namespace = "firework"
  secrets_mount = "/etc/firework"
  config_mount  = "/etc/firework-config"
  config_file   = "/etc/firework-config/controlplane.yaml"

  events_config = yamlencode({
    role               = "events"
    events_listen_addr = ":${var.events_port}"
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
    registry_listen_addr = ":${var.registry_port}"
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

  api_config = yamlencode({
    role            = "api"
    api_listen_addr = ":${var.api_port}"
    state = {
      backend = "gcs"
      prefix  = var.state_prefix
      gcs = {
        bucket  = google_storage_bucket.state.name
        project = var.gcp_project
      }
    }
    node_stale_ttl      = var.node_stale_ttl
    operator_token_file = "${local.secrets_mount}/secrets/operator-token"
    tls = {
      cert_file = "${local.secrets_mount}/tls/server.crt"
      key_file  = "${local.secrets_mount}/tls/server.key"
    }
  })

  events_csi_secrets = concat([
    {
      resourceName = "projects/${var.gcp_project}/secrets/${local.effective_webhook_secret_id}/versions/latest"
      path         = "secrets/webhook-secret"
    },
    {
      resourceName = "projects/${var.gcp_project}/secrets/${local.effective_events_tls_cert_secret_id}/versions/latest"
      path         = "tls/server.crt"
    },
    {
      resourceName = "projects/${var.gcp_project}/secrets/${local.effective_events_tls_key_secret_id}/versions/latest"
      path         = "tls/server.key"
    },
    ], var.github_token_secret_id != "" ? [{
      resourceName = "projects/${var.gcp_project}/secrets/${var.github_token_secret_id}/versions/latest"
      path         = "secrets/github-token"
  }] : [])

  registry_csi_secrets = [
    {
      resourceName = "projects/${var.gcp_project}/secrets/${local.effective_bootstrap_token_secret_id}/versions/latest"
      path         = "secrets/bootstrap-token"
    },
    {
      resourceName = "projects/${var.gcp_project}/secrets/${local.effective_registry_tls_cert_secret_id}/versions/latest"
      path         = "tls/server.crt"
    },
    {
      resourceName = "projects/${var.gcp_project}/secrets/${local.effective_registry_tls_key_secret_id}/versions/latest"
      path         = "tls/server.key"
    },
    {
      resourceName = "projects/${var.gcp_project}/secrets/${local.effective_enrollment_ca_cert_secret_id}/versions/latest"
      path         = "tls/enrollment-ca.crt"
    },
    {
      resourceName = "projects/${var.gcp_project}/secrets/${local.effective_enrollment_ca_key_secret_id}/versions/latest"
      path         = "tls/enrollment-ca.key"
    },
  ]

  api_csi_secrets = [
    {
      resourceName = "projects/${var.gcp_project}/secrets/${local.effective_events_tls_cert_secret_id}/versions/latest"
      path         = "tls/server.crt"
    },
    {
      resourceName = "projects/${var.gcp_project}/secrets/${local.effective_events_tls_key_secret_id}/versions/latest"
      path         = "tls/server.key"
    },
    {
      resourceName = "projects/${var.gcp_project}/secrets/${local.effective_operator_token_secret_id}/versions/latest"
      path         = "secrets/operator-token"
    },
  ]
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
  for_each = local.controlplane_roles

  metadata {
    name      = each.value.ksa_name
    namespace = kubernetes_namespace.firework.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.controlplane[each.key].email
    }
  }
}

# Secret Manager CSI volumes keep secret values out of Kubernetes Secret
# objects and Terraform state when the operator supplies the secret material.
resource "kubectl_manifest" "events_secret_provider_class" {
  yaml_body = yamlencode({
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "firework-events-secrets"
      namespace = kubernetes_namespace.firework.metadata[0].name
    }
    spec = {
      provider = "gke"
      parameters = {
        secrets = yamlencode(local.events_csi_secrets)
      }
    }
  })

  # The CRD is installed by the GKE Secret Manager CSI add-on, not by this
  # configuration, so defer client-side schema validation to the API server.
  validate_schema = false

  depends_on = [
    google_container_cluster.control_plane,
    kubernetes_namespace.firework,
    google_secret_manager_secret_iam_member.controlplane_accessor,
  ]
}

resource "kubectl_manifest" "registry_secret_provider_class" {
  yaml_body = yamlencode({
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "firework-registry-secrets"
      namespace = kubernetes_namespace.firework.metadata[0].name
    }
    spec = {
      provider = "gke"
      parameters = {
        secrets = yamlencode(local.registry_csi_secrets)
      }
    }
  })

  validate_schema = false

  depends_on = [
    google_container_cluster.control_plane,
    kubernetes_namespace.firework,
    google_secret_manager_secret_iam_member.controlplane_accessor,
  ]
}

resource "kubectl_manifest" "api_secret_provider_class" {
  yaml_body = yamlencode({
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "firework-api-secrets"
      namespace = kubernetes_namespace.firework.metadata[0].name
    }
    spec = {
      provider = "gke"
      parameters = {
        secrets = yamlencode(local.api_csi_secrets)
      }
    }
  })

  validate_schema = false

  depends_on = [
    google_container_cluster.control_plane,
    kubernetes_namespace.firework,
    google_secret_manager_secret_iam_member.controlplane_accessor,
  ]
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

resource "kubernetes_config_map" "api" {
  metadata {
    name      = "firework-api-config"
    namespace = kubernetes_namespace.firework.metadata[0].name
  }
  data = {
    "controlplane.yaml" = local.api_config
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
        service_account_name = kubernetes_service_account.controlplane["events"].metadata[0].name

        container {
          name    = "controlplane"
          image   = var.controlplane_image
          command = ["/bin/sh", "-ec"]
          args = [var.github_token_secret_id != "" ?
            "export GITHUB_TOKEN=\"$(cat ${local.secrets_mount}/secrets/github-token)\"; exec /usr/local/bin/firework-controlplane --config ${local.config_file}" :
            "exec /usr/local/bin/firework-controlplane --config ${local.config_file}"
          ]

          port {
            name           = "events"
            container_port = var.events_port
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }

          readiness_probe {
            http_get {
              path   = "/healthz"
              port   = var.events_port
              scheme = "HTTPS"
            }
            initial_delay_seconds = 10
            period_seconds        = 15
            failure_threshold     = 3
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
            name = kubernetes_config_map.events.metadata[0].name
          }
        }

        volume {
          name = "secrets"
          csi {
            driver    = "secrets-store-gke.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = "firework-events-secrets"
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubectl_manifest.events_secret_provider_class,
    google_storage_bucket_iam_member.state_object_admin,
    google_service_account_iam_member.workload_identity,
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
        service_account_name = kubernetes_service_account.controlplane["registry"].metadata[0].name

        container {
          name  = "controlplane"
          image = var.controlplane_image
          args  = ["--config", local.config_file]

          port {
            name           = "registry"
            container_port = var.registry_port
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
            driver    = "secrets-store-gke.csi.k8s.io"
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
    kubectl_manifest.registry_secret_provider_class,
    google_storage_bucket_iam_member.state_object_admin,
    google_service_account_iam_member.workload_identity,
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
        service_account_name = kubernetes_service_account.controlplane["controller"].metadata[0].name

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

        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.controller.metadata[0].name
          }
        }

      }
    }
  }

  depends_on = [
    google_storage_bucket_iam_member.state_object_admin,
    google_service_account_iam_member.workload_identity,
  ]
}

resource "kubernetes_deployment" "api" {
  metadata {
    name      = "firework-api"
    namespace = kubernetes_namespace.firework.metadata[0].name
    labels    = merge(local.common_labels, { role = "api" })
  }
  spec {
    replicas = var.api_replicas
    selector {
      match_labels = { role = "api" }
    }
    template {
      metadata {
        labels = merge(local.common_labels, { role = "api" })
      }
      spec {
        service_account_name = kubernetes_service_account.controlplane["api"].metadata[0].name

        container {
          name  = "controlplane"
          image = var.controlplane_image
          args  = ["--config", local.config_file]

          port {
            name           = "api"
            container_port = var.api_port
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }

          readiness_probe {
            http_get {
              path   = "/healthz"
              port   = var.api_port
              scheme = "HTTPS"
            }
            initial_delay_seconds = 10
            period_seconds        = 15
            failure_threshold     = 3
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
            name = kubernetes_config_map.api.metadata[0].name
          }
        }

        volume {
          name = "secrets"
          csi {
            driver    = "secrets-store-gke.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = "firework-api-secrets"
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubectl_manifest.api_secret_provider_class,
    google_storage_bucket_iam_member.state_object_viewer,
    google_service_account_iam_member.workload_identity,
  ]
}

# ---------------------------------------------------------------------------
# Services and hostname-separated Gateway API routing (GKE L7 HTTPS LB)
# ---------------------------------------------------------------------------

resource "kubernetes_service" "events" {
  metadata {
    name      = "firework-events"
    namespace = kubernetes_namespace.firework.metadata[0].name
    labels    = merge(local.common_labels, { role = "events" })
  }
  spec {
    type     = "ClusterIP"
    selector = { role = "events" }

    port {
      name         = "https"
      port         = var.events_port
      target_port  = var.events_port
      protocol     = "TCP"
      app_protocol = "HTTPS"
    }
  }
}

resource "kubernetes_service" "api" {
  metadata {
    name      = "firework-api"
    namespace = kubernetes_namespace.firework.metadata[0].name
    labels    = merge(local.common_labels, { role = "api" })
  }
  spec {
    type     = "ClusterIP"
    selector = { role = "api" }

    port {
      name         = "https"
      port         = var.api_port
      target_port  = var.api_port
      protocol     = "TCP"
      app_protocol = "HTTPS"
    }
  }
}

resource "kubectl_manifest" "events_gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "firework-events"
      namespace = kubernetes_namespace.firework.metadata[0].name
      labels    = merge(local.common_labels, { role = "events" })
      annotations = {
        "networking.gke.io/certmap" = local.effective_events_certificate_map_name
      }
    }
    spec = {
      gatewayClassName = "gke-l7-global-external-managed"
      addresses = [{
        type  = "NamedAddress"
        value = local.effective_events_gateway_address_name
      }]
      listeners = [{
        name     = "https"
        protocol = "HTTPS"
        port     = 443
        allowedRoutes = {
          namespaces = {
            from = "Same"
          }
        }
      }]
    }
  })

  validate_schema = false

  depends_on = [
    google_container_cluster.control_plane,
    kubernetes_namespace.firework,
    terraform_data.validate_events_edge_wiring,
  ]
}

resource "kubectl_manifest" "events_route" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "firework-events"
      namespace = kubernetes_namespace.firework.metadata[0].name
      labels    = merge(local.common_labels, { role = "events" })
    }
    spec = {
      parentRefs = [{
        name        = "firework-events"
        sectionName = "https"
      }]
      hostnames = [trimsuffix(var.events_domain, ".")]
      rules = [
        {
          matches = [{
            path = {
              type  = "Exact"
              value = "/v1/events/github"
            }
          }]
          backendRefs = [{
            name = kubernetes_service.events.metadata[0].name
            port = var.events_port
          }]
        }
      ]
    }
  })

  validate_schema = false

  depends_on = [
    kubectl_manifest.events_gateway,
    kubernetes_service.events,
  ]
}

resource "kubectl_manifest" "status_route" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "firework-status"
      namespace = kubernetes_namespace.firework.metadata[0].name
      labels    = merge(local.common_labels, { role = "api" })
    }
    spec = {
      parentRefs = [{
        name        = "firework-events"
        sectionName = "https"
      }]
      hostnames = [local.effective_status_domain]
      rules = [{
        matches = [{
          path = {
            type  = "PathPrefix"
            value = "/"
          }
        }]
        backendRefs = [{
          name = kubernetes_service.api.metadata[0].name
          port = var.api_port
        }]
      }]
    }
  })

  validate_schema = false

  depends_on = [
    kubectl_manifest.events_gateway,
    kubernetes_service.api,
  ]
}

# Gateway does not infer the Events readiness probe. Without this policy it
# would issue HTTPS checks to /, while firework-controlplane exposes /healthz.
resource "kubectl_manifest" "events_health_check" {
  yaml_body = yamlencode({
    apiVersion = "networking.gke.io/v1"
    kind       = "HealthCheckPolicy"
    metadata = {
      name      = "firework-events"
      namespace = kubernetes_namespace.firework.metadata[0].name
    }
    spec = {
      default = {
        checkIntervalSec   = 15
        timeoutSec         = 5
        healthyThreshold   = 1
        unhealthyThreshold = 3
        config = {
          type = "HTTPS"
          httpsHealthCheck = {
            portSpecification = "USE_FIXED_PORT"
            port              = var.events_port
            requestPath       = "/healthz"
          }
        }
      }
      targetRef = {
        group = ""
        kind  = "Service"
        name  = kubernetes_service.events.metadata[0].name
      }
    }
  })

  validate_schema = false

  depends_on = [
    kubectl_manifest.events_route,
    kubernetes_service.events,
  ]
}

resource "kubectl_manifest" "api_health_check" {
  yaml_body = yamlencode({
    apiVersion = "networking.gke.io/v1"
    kind       = "HealthCheckPolicy"
    metadata = {
      name      = "firework-api"
      namespace = kubernetes_namespace.firework.metadata[0].name
    }
    spec = {
      default = {
        checkIntervalSec   = 15
        timeoutSec         = 5
        healthyThreshold   = 1
        unhealthyThreshold = 3
        config = {
          type = "HTTPS"
          httpsHealthCheck = {
            portSpecification = "USE_FIXED_PORT"
            port              = var.api_port
            requestPath       = "/healthz"
          }
        }
      }
      targetRef = {
        group = ""
        kind  = "Service"
        name  = kubernetes_service.api.metadata[0].name
      }
    }
  })

  validate_schema = false

  depends_on = [
    kubectl_manifest.status_route,
    kubernetes_service.api,
  ]
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
      port        = var.registry_port
      target_port = var.registry_port
      protocol    = "TCP"
    }
  }
}
