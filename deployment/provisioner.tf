resource "kubernetes_namespace" "provisioner-ns" {
  metadata {
    name = "mvd-provisioner"
  }
}

resource "kubernetes_service_account" "provisioner-sa" {
  metadata {
    name      = "provisioner"
    namespace = kubernetes_namespace.provisioner-ns.metadata.0.name
  }
}

resource "kubernetes_cluster_role" "provisioner-cr" {
  metadata {
    name = "namespace-patcher"
  }
  rule {
    verbs      = ["get", "patch", "update", "delete", "create"]
    resources  = ["namespaces", "pods", "services", "configmaps", "deployments", "ingresses"]
    api_groups = ["", "apps", "networking.k8s.io"]
  }
}

resource "kubernetes_cluster_role_binding" "provisioner-crb" {
  metadata {
    name = "namespace-patcher-binding"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.provisioner-sa.metadata.0.name
    namespace = kubernetes_namespace.provisioner-ns.metadata.0.name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.provisioner-cr.metadata.0.name
  }
}

resource "kubernetes_secret" "ghcr-secret" {
  metadata {
    name      = "ghcr-secret"
    namespace = kubernetes_namespace.provisioner-ns.metadata.0.name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.ghcr_username
          password = var.ghcr_pat
          auth     = base64encode("${var.ghcr_username}:${var.ghcr_pat}")
        }
      }
    })
  }
}


resource "kubernetes_deployment" "go-provisioner" {
  metadata {
    name      = "go-provisioner"
    namespace = kubernetes_namespace.provisioner-ns.metadata.0.name
  }
  spec {
    replicas = "1"
    selector {
      match_labels = {
        app = "go-provisioner"
      }
    }
    template {
      metadata {
        labels = {
          app = "go-provisioner"
        }
      }
      spec {
        service_account_name = kubernetes_service_account.provisioner-sa.metadata.0.name
        image_pull_secrets {
          name = "ghcr-secret"
        }
        container {
          name              = "go-provisioner"
          image             = "ghcr.io/paullatzelsperger/go-provisioner:latest"
          image_pull_policy = "Always"
          port {
            container_port = 9999
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "go-provisioner-service" {
  metadata {
    name      = "go-provisioner-service"
    namespace = kubernetes_namespace.provisioner-ns.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.go-provisioner.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 9999
      target_port = 9999
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_ingress_v1" "provisioner-ingress" {
  metadata {
    name      = "go-provisioner"
    namespace = kubernetes_namespace.provisioner-ns.metadata.0.name
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" = "/$2"
      "nginx.ingress.kubernetes.io/use-regex"      = "true"
    }
  }
  spec {
    ingress_class_name = "nginx"
    rule {
      http {
        path {
          path = "/provisioner(/|$)(.*)"
          backend {

            service {
              name = kubernetes_service.go-provisioner-service.metadata.0.name
              port {
                number = 9999
              }
            }
          }
        }
      }
    }
  }

}
