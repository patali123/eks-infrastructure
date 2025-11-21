# Universal Terraform Patterns for Kubernetes Tool Integration

## 🎯 Core Concept
**Almost ALL Kubernetes tools follow 3-5 standard Terraform patterns. Master these, and you can integrate ANY tool.**

---

## 📋 The 5 Universal Patterns

### Pattern 1: Helm Release (80% of tools)
### Pattern 2: Kubectl Apply (YAML manifests)
### Pattern 3: IAM Role + Service Account (AWS IRSA)
### Pattern 4: Provider Configuration (Tool-specific providers)
### Pattern 5: Custom Resource Definitions (CRDs)

---

## 🔧 PATTERN 1: Helm Release (Most Common)

**When to use:** Tool has official Helm chart (Prometheus, Grafana, Istio, ArgoCD, etc.)

### Basic Template
```hcl
# File: terraform/helm-<tool-name>.tf

# 1. Add Helm repository data source (optional but cleaner)
data "helm_repository" "tool_repo" {
  name = "<tool-name>"
  url  = "https://<org>.github.io/<chart-repo>"
}

# 2. Deploy with helm_release
resource "helm_release" "tool_name" {
  name       = "<release-name>"
  repository = data.helm_repository.tool_repo.url  # or direct URL
  chart      = "<chart-name>"
  namespace  = "<namespace>"
  version    = "<chart-version>"

  create_namespace = true  # Auto-create namespace

  # Override default values
  values = [
    file("${path.module}/values/<tool-name>-values.yaml")
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

  # Dependencies
  depends_on = [
    aws_eks_cluster.eks,
    helm_release.prerequisite_tool
  ]
}
```

### Real Example: Prometheus
```hcl
# terraform/helm-prometheus.tf

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  version    = "55.5.0"

  create_namespace = true

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password  # Use variable for secrets
  }

  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "30d"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = "50Gi"
  }

  depends_on = [aws_eks_node_group.general]
}
```

### Real Example: ArgoCD
```hcl
# terraform/helm-argocd.tf

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  version    = "5.51.4"

  create_namespace = true

  values = [
    file("${path.module}/values/argocd-values.yaml")
  ]

  depends_on = [helm_release.prometheus]
}
```

### Real Example: Istio (via Helm)
```hcl
# terraform/helm-istio.tf

# Istio base (CRDs)
resource "helm_release" "istio_base" {
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  namespace  = "istio-system"
  version    = "1.20.0"

  create_namespace = true
}

# Istio control plane
resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = "istio-system"
  version    = "1.20.0"

  set {
    name  = "pilot.resources.requests.memory"
    value = "2Gi"
  }

  depends_on = [helm_release.istio_base]
}

# Istio ingress gateway
resource "helm_release" "istio_ingress" {
  name       = "istio-ingress"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = "istio-ingress"
  version    = "1.20.0"

  create_namespace = true

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  depends_on = [helm_release.istiod]
}
```

---

## 🔧 PATTERN 2: Kubectl Apply (Direct YAML)

**When to use:** No Helm chart available, or you want exact control over manifests

### Basic Template
```hcl
# File: terraform/kubectl-<tool-name>.tf

# Option A: Using kubectl provider
resource "kubectl_manifest" "tool_manifest" {
  yaml_body = file("${path.module}/manifests/<tool-name>.yaml")

  depends_on = [aws_eks_cluster.eks]
}

# Option B: Multiple manifests
resource "kubectl_manifest" "tool_manifests" {
  for_each = fileset("${path.module}/manifests/<tool-name>", "*.yaml")

  yaml_body = file("${path.module}/manifests/<tool-name>/${each.value}")

  depends_on = [aws_eks_cluster.eks]
}

# Option C: Using kubernetes provider
resource "kubernetes_manifest" "tool_crd" {
  manifest = yamldecode(file("${path.module}/manifests/crd.yaml"))

  depends_on = [aws_eks_cluster.eks]
}
```

### Real Example: Cilium (via kubectl)
```hcl
# terraform/kubectl-cilium.tf

# Install Cilium using kubectl provider
resource "kubectl_manifest" "cilium_install" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: cilium
  YAML
}

# Or use null_resource with local-exec
resource "null_resource" "install_cilium" {
  provisioner "local-exec" {
    command = <<-EOT
      cilium install \
        --version 1.14.5 \
        --set ipam.mode=kubernetes \
        --set kubeProxyReplacement=strict
    EOT
  }

  depends_on = [aws_eks_cluster.eks]
}
```

### Real Example: Kyverno
```hcl
# terraform/kubectl-kyverno.tf

resource "kubectl_manifest" "kyverno_install" {
  yaml_body = file("${path.module}/manifests/kyverno-install.yaml")

  depends_on = [
    aws_eks_cluster.eks,
    helm_release.prometheus
  ]
}

# Or using Helm (Kyverno has Helm chart)
resource "helm_release" "kyverno" {
  name       = "kyverno"
  repository = "https://kyverno.github.io/kyverno/"
  chart      = "kyverno"
  namespace  = "kyverno"
  version    = "3.1.4"

  create_namespace = true

  set {
    name  = "replicaCount"
    value = 3
  }

  depends_on = [helm_release.prometheus]
}
```

---

## 🔧 PATTERN 3: IAM Role + Service Account (AWS IRSA)

**When to use:** Tool needs AWS permissions (Cluster Autoscaler, AWS Load Balancer Controller, ExternalDNS, etc.)

### Universal Template
```hcl
# File: terraform/iam-<tool-name>.tf

# 1. Create IAM policy with required permissions
resource "aws_iam_policy" "tool_policy" {
  name        = "${var.cluster_name}-<tool-name>"
  description = "IAM policy for <tool-name>"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "<service>:<action>",
          "<service>:<action>"
        ]
        Resource = "*"  # or specific resources
      }
    ]
  })
}

# 2. Create IAM role with EKS trust relationship
resource "aws_iam_role" "tool_role" {
  name = "${var.cluster_name}-<tool-name>"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:<namespace>:<service-account-name>"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# 3. Attach policy to role
resource "aws_iam_role_policy_attachment" "tool_policy_attach" {
  role       = aws_iam_role.tool_role.name
  policy_arn = aws_iam_policy.tool_policy.arn
}

# 4. Create Kubernetes service account with annotation
resource "kubernetes_service_account" "tool_sa" {
  metadata {
    name      = "<service-account-name>"
    namespace = "<namespace>"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.tool_role.arn
    }
  }

  depends_on = [aws_eks_cluster.eks]
}

# 5. Deploy tool with Helm, referencing service account
resource "helm_release" "tool" {
  name       = "<tool-name>"
  repository = "<repo-url>"
  chart      = "<chart>"
  namespace  = "<namespace>"

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.tool_sa.metadata[0].name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"  # We created it above
  }

  depends_on = [
    kubernetes_service_account.tool_sa,
    aws_iam_role_policy_attachment.tool_policy_attach
  ]
}
```

### Real Example: AWS Load Balancer Controller
```hcl
# terraform/iam-aws-load-balancer-controller.tf

# Download IAM policy from AWS
data "http" "alb_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "alb_controller" {
  name   = "${var.cluster_name}-alb-controller"
  policy = data.http.alb_iam_policy.response_body
}

resource "aws_iam_role" "alb_controller" {
  name = "${var.cluster_name}-alb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
    }
  }
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.1"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.eks.name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.alb_controller.metadata[0].name
  }

  depends_on = [
    kubernetes_service_account.alb_controller,
    aws_iam_role_policy_attachment.alb_controller
  ]
}
```

### Real Example: Cluster Autoscaler (Pod Identity)
```hcl
# terraform/iam-cluster-autoscaler.tf

# Using EKS Pod Identity (newer method)
resource "aws_iam_role" "cluster_autoscaler" {
  name = "${aws_eks_cluster.eks.name}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["sts:AssumeRole", "sts:TagSession"]
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name = "${aws_eks_cluster.eks.name}-cluster-autoscaler"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeInstanceTypes",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
  role       = aws_iam_role.cluster_autoscaler.name
}

# Pod Identity Association
resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  cluster_name    = aws_eks_cluster.eks.name
  namespace       = "kube-system"
  service_account = "cluster-autoscaler"
  role_arn        = aws_iam_role.cluster_autoscaler.arn
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.37.0"

  set = [
    {
      name  = "rbac.serviceAccount.name"
      value = "cluster-autoscaler"
    },
    {
      name  = "autoDiscovery.clusterName"
      value = aws_eks_cluster.eks.name
    },
    {
      name  = "awsRegion"
      value = var.region
    }
  ]

  depends_on = [aws_eks_pod_identity_association.cluster_autoscaler]
}
```

---

## 🔧 PATTERN 4: Provider Configuration

**When to use:** Tool has its own Terraform provider (Helm, Kubectl, Kubernetes)

### Providers Setup
```hcl
# File: terraform/providers.tf

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

# AWS Provider
provider "aws" {
  region = var.region
}

# Get EKS cluster info
data "aws_eks_cluster" "eks" {
  name = aws_eks_cluster.eks.name
}

data "aws_eks_cluster_auth" "eks" {
  name = aws_eks_cluster.eks.name
}

# Kubernetes Provider
provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

# Helm Provider
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}

# Kubectl Provider
provider "kubectl" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
  load_config_file       = false
}
```

---

## 🔧 PATTERN 5: Custom Resource Definitions (CRDs)

**When to use:** Tool requires CRDs before main installation (Istio, Prometheus Operator, ArgoCD)

### Basic Template
```hcl
# File: terraform/crds-<tool-name>.tf

# Option A: Apply CRDs from URL
resource "kubectl_manifest" "tool_crds" {
  yaml_body = data.http.tool_crds.response_body

  depends_on = [aws_eks_cluster.eks]
}

data "http" "tool_crds" {
  url = "https://raw.githubusercontent.com/<org>/<repo>/main/crds.yaml"
}

# Option B: Apply CRDs from local files
resource "kubectl_manifest" "tool_crds" {
  for_each = fileset("${path.module}/crds/<tool-name>", "*.yaml")

  yaml_body = file("${path.module}/crds/<tool-name>/${each.value}")

  depends_on = [aws_eks_cluster.eks]
}

# Option C: Helm chart with CRDs
resource "helm_release" "tool_crds" {
  name       = "<tool>-crds"
  repository = "<repo-url>"
  chart      = "<tool>-crds"
  namespace  = "kube-system"

  skip_crds = false  # Ensure CRDs are installed

  depends_on = [aws_eks_cluster.eks]
}

# Then install main tool
resource "helm_release" "tool" {
  name       = "<tool>"
  repository = "<repo-url>"
  chart      = "<tool>"
  namespace  = "<namespace>"

  depends_on = [helm_release.tool_crds]
}
```

### Real Example: Prometheus Operator
```hcl
# terraform/helm-prometheus.tf

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  version    = "55.5.0"

  create_namespace = true

  # CRDs are included in chart by default
  # If you want to manage CRDs separately:
  skip_crds = false

  depends_on = [aws_eks_node_group.general]
}
```

---

## 📁 Recommended File Structure

```
terraform/
├── providers.tf                    # All provider configurations
├── variables.tf                    # Input variables
├── outputs.tf                      # Outputs
├── eks-cluster.tf                  # EKS cluster definition
├── eks-node-groups.tf              # Node groups
├── eks-oidc.tf                     # OIDC provider for IRSA
│
├── helm-prometheus.tf              # Pattern 1: Helm
├── helm-grafana.tf
├── helm-argocd.tf
├── helm-istio.tf
├── helm-kyverno.tf
├── helm-argo-rollouts.tf
│
├── iam-cluster-autoscaler.tf       # Pattern 3: IAM + IRSA
├── iam-alb-controller.tf
├── iam-external-dns.tf
│
├── kubectl-cilium.tf               # Pattern 2: kubectl apply
│
└── values/                         # Helm values files
    ├── prometheus-values.yaml
    ├── argocd-values.yaml
    └── istio-values.yaml
```

---

## 🎯 Universal Decision Tree

```
New Tool to Install?
│
├─ Has Helm Chart? ────────────────► Use Pattern 1 (Helm)
│   └─ Needs AWS Permissions? ────► Add Pattern 3 (IAM + IRSA)
│
├─ Only YAML manifests? ───────────► Use Pattern 2 (kubectl)
│   └─ Needs AWS Permissions? ────► Add Pattern 3 (IAM + IRSA)
│
├─ Has CRDs? ──────────────────────► Use Pattern 5 first, then Pattern 1 or 2
│
└─ Custom Tool/Provider? ──────────► Use Pattern 4 + specific provider
```

---

## 🚀 Step-by-Step Integration Process (ANY Tool)

### Step 1: Research (10 min)
```bash
# Check if Helm chart exists
helm search hub <tool-name>

# Check official docs for installation methods
# Look for: Helm, kubectl, Terraform module

# Check if AWS permissions needed
# Keywords: IAM, IRSA, Pod Identity, AWS SDK
```

### Step 2: Choose Pattern (5 min)
- **Has Helm chart?** → Pattern 1
- **YAML only?** → Pattern 2
- **Needs AWS access?** → Add Pattern 3
- **Has CRDs?** → Add Pattern 5 first

### Step 3: Create Terraform File (15-30 min)
```bash
# Create file
touch terraform/helm-<tool-name>.tf

# OR if IAM needed
touch terraform/iam-<tool-name>.tf
```

### Step 4: Apply Template (10 min)
Copy relevant pattern from above, customize:
- `<tool-name>` → actual tool name
- `<namespace>` → target namespace
- `<chart-version>` → specific version
- `<repo-url>` → Helm repo URL

### Step 5: Customize Values (20 min)
```bash
# Get default values
helm show values <repo>/<chart> > values/<tool>-default.yaml

# Create custom values
cp values/<tool>-default.yaml values/<tool>-values.yaml
# Edit values/<tool>-values.yaml
```

### Step 6: Plan & Apply (10 min)
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Step 7: Verify (10 min)
```bash
# Check pods
kubectl get pods -n <namespace>

# Check Helm release
helm list -n <namespace>

# Test functionality (tool-specific)
```

---

## 📝 Real-World Example: Adding New Tool (ExternalDNS)

### Step 1: Research
```bash
helm search hub external-dns
# Found: bitnami/external-dns

# Check docs: https://github.com/kubernetes-sigs/external-dns
# Needs: AWS Route53 permissions
```

### Step 2: Choose Pattern
- ✅ Has Helm chart → Pattern 1
- ✅ Needs AWS permissions → Pattern 3
- ❌ No special CRDs → Skip Pattern 5

### Step 3-4: Create File
```hcl
# terraform/iam-external-dns.tf

# IAM Policy
resource "aws_iam_policy" "external_dns" {
  name = "${var.cluster_name}-external-dns"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "route53:ChangeResourceRecordSets",
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets"
      ]
      Resource = "*"
    }]
  })
}

# IAM Role
resource "aws_iam_role" "external_dns" {
  name = "${var.cluster_name}-external-dns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:external-dns"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

# Service Account
resource "kubernetes_service_account" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn
    }
  }
}

# Helm Release
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "external-dns"
  namespace  = "kube-system"
  version    = "6.31.4"

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.external_dns.metadata[0].name
  }

  set {
    name  = "policy"
    value = "sync"  # or "upsert-only"
  }

  depends_on = [
    kubernetes_service_account.external_dns,
    aws_iam_role_policy_attachment.external_dns
  ]
}
```

### Step 5: Apply
```bash
terraform plan
terraform apply
```

### Step 6: Verify
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=external-dns
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns
```

**Done! 🎉 You just integrated a new tool following the patterns.**

---

## 💡 Pro Tips

### Tip 1: Use Variables for Reusability
```hcl
# variables.tf
variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type    = string
  default = "dev"
}

# Use in resources
resource "helm_release" "tool" {
  name      = "${var.environment}-tool"
  namespace = "tool-${var.environment}"
  # ...
}
```

### Tip 2: Use Locals for Common Values
```hcl
# locals.tf
locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Cluster     = var.cluster_name
  }

  oidc_provider_arn = aws_iam_openid_connect_provider.eks.arn
  oidc_provider_url = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

# Use in IAM roles
resource "aws_iam_role" "tool_role" {
  name = "${var.cluster_name}-tool"
  tags = local.common_tags
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
```

### Tip 3: Use Outputs for Debugging
```hcl
# outputs.tf
output "helm_releases" {
  value = {
    prometheus = helm_release.prometheus.status
    argocd     = helm_release.argocd.status
    istio      = helm_release.istiod.status
  }
}

output "iam_roles" {
  value = {
    cluster_autoscaler = aws_iam_role.cluster_autoscaler.arn
    alb_controller     = aws_iam_role.alb_controller.arn
  }
}
```

### Tip 4: Use depends_on Carefully
```hcl
# Always specify dependencies for:
# 1. Helm releases that depend on CRDs
# 2. Tools that need other tools first
# 3. IAM resources before Kubernetes resources

resource "helm_release" "istio_base" {
  # ...
}

resource "helm_release" "istiod" {
  # ...
  depends_on = [helm_release.istio_base]  # CRDs first
}

resource "helm_release" "argo_rollouts" {
  # ...
  depends_on = [helm_release.istiod]  # Needs Istio
}
```

### Tip 5: Use Lifecycle Rules
```hcl
resource "helm_release" "tool" {
  name = "tool"
  # ...

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_service_account" "tool" {
  # ...

  # Ignore external changes
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}
```

---

## 🔥 Quick Reference Cheat Sheet

| Tool Type | Pattern | Key Files | Dependencies |
|-----------|---------|-----------|--------------|
| **Monitoring** (Prometheus, Grafana) | Helm (1) | `helm-<tool>.tf` | EKS cluster |
| **Logging** (Loki, Fluentd) | Helm (1) | `helm-<tool>.tf` | EKS cluster |
| **GitOps** (ArgoCD, Flux) | Helm (1) | `helm-<tool>.tf` | Monitoring |
| **Service Mesh** (Istio, Linkerd) | Helm (1) + CRDs (5) | `helm-<tool>.tf` | Monitoring, GitOps |
| **Policy** (Kyverno, OPA) | Helm (1) | `helm-<tool>.tf` | GitOps |
| **Progressive** (Argo Rollouts) | Helm (1) | `helm-<tool>.tf` | Service Mesh |
| **AWS Tools** (ALB, ExternalDNS) | Helm (1) + IAM (3) | `iam-<tool>.tf` | OIDC provider |
| **Custom** (Cilium, custom) | kubectl (2) | `kubectl-<tool>.tf` | EKS cluster |

---

## 🎓 Practice Exercise

Try adding **cert-manager** to your cluster:

1. **Research**: Has Helm chart? Needs AWS permissions?
2. **Choose Pattern**: Helm (1) + optional Route53 IAM (3)
3. **Create File**: `terraform/helm-cert-manager.tf`
4. **Apply Template**: Use Pattern 1
5. **Customize**: Set up ClusterIssuer for Let's Encrypt
6. **Apply**: `terraform apply`
7. **Verify**: Check pods and create test Certificate

### Hint:
```hcl
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = "v1.13.3"

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [aws_eks_node_group.general]
}
```

---

## 🎯 Summary

**5 Universal Patterns:**
1. **Helm Release** → 80% of tools
2. **Kubectl Apply** → YAML manifests
3. **IAM + IRSA** → AWS permissions
4. **Provider Config** → Foundation
5. **CRDs** → Before main install

**Integration Steps (ANY Tool):**
1. Research (Helm? IAM? CRDs?)
2. Choose pattern(s)
3. Copy template
4. Customize values
5. Apply
6. Verify

**Follow this process, and you can integrate ANY Kubernetes tool in 1-2 hours!** 🚀

---

Need help integrating a specific tool? Just tell me which one, and I'll generate the exact Terraform code following these patterns!
