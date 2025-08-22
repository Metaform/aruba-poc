resource "kubernetes_namespace" "provisioner-ns" {
  metadata {
    name = "poc-provisioner"
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


resource "kubernetes_deployment" "provisioner" {
  metadata {
    name      = "provisioner"
    namespace = kubernetes_namespace.provisioner-ns.metadata.0.name
  }
  spec {
    replicas = "1"
    selector {
      match_labels = {
        app = "provisioner"
      }
    }
    template {
      metadata {
        labels = {
          app = "provisioner"
        }
      }
      spec {
        service_account_name = kubernetes_service_account.provisioner-sa.metadata.0.name
        container {
          name              = "provisioner"
          image             = "ghcr.io/metaform/aruba-provisioner:latest"
          image_pull_policy = "Always"
          port {
            container_port = 9999
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "provisioner-service" {
  metadata {
    name      = "provisioner-service"
    namespace = kubernetes_namespace.provisioner-ns.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.provisioner.spec.0.template.0.metadata.0.labels.app
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
    name      = "provisioner"
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
              name = kubernetes_service.provisioner-service.metadata.0.name
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
