# File: terraform/helm-<tool-name>.tf

# 1. Add Helm repository data source (optional but cleaner)
data "helm_repository" "cilium_repo" {
  name = "cilium"
  url  = "https://helm.cilium.io/"
}

# 2. Deploy with helm_release
resource "helm_release" "cilium" {
  name       = "cilium"
  repository = data.helm_repository.cilium_repo.url  # or direct URL
  chart      = "cilium"
  namespace  = "cilium"
  version    = "1.18.4"

  create_namespace = true  # Auto-create namespace

  # Override default values
  values = [
    file("${path.module}/values/cilium-values.yaml")
  ]

  # Or inline values
  set {
    name  = "key.subkey"
    value = "value"
  }

  set {
    name  = "replicas"
    value = 3
  }

  # Dependencies (uncomment and adjust as needed)
  # depends_on = [
  #   aws_eks_cluster.eks,
  #   helm_release.prerequisite_tool
  # ]
}