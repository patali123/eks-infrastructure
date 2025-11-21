# Universal EKS Troubleshooting Guide
## Systematic Approach to Debug ANY Kubernetes/EKS Issue

---

## 🎯 Core Philosophy

**"Follow the data flow, check each layer systematically, eliminate possibilities."**

Every EKS issue falls into one of these categories:
1. Infrastructure (AWS/EKS cluster)
2. Networking (CNI, DNS, connectivity)
3. Compute (nodes, pods, containers)
4. Configuration (manifests, Helm charts)
5. Permissions (IAM, RBAC)
6. Application (code, dependencies)
7. Tool-specific (Istio, ArgoCD, etc.)

---

## 📋 THE UNIVERSAL TROUBLESHOOTING PROCESS

### 🔍 Phase 1: GATHER CONTEXT (5 min)
**Before touching anything, understand the problem.**

```bash
# What's the symptom?
# - Pod not starting?
# - Service unreachable?
# - Deployment stuck?
# - High latency?
# - Authentication failure?

# Ask these questions:
1. What changed recently? (deployment, config, upgrade?)
2. Is it affecting all pods or specific ones?
3. Is it intermittent or consistent?
4. When did it start?
5. What's the error message (exact text)?
```

### 🔍 Phase 2: CHECK CLUSTER HEALTH (5 min)
**Ensure the foundation is solid.**

```bash
# 1. Check cluster status
aws eks describe-cluster --name <cluster-name> --query 'cluster.status'
# Should be: ACTIVE

# 2. Check API server
kubectl cluster-info
kubectl get --raw='/readyz?verbose'

# 3. Check nodes
kubectl get nodes
kubectl top nodes  # Resource usage
kubectl describe node <node-name>  # If issues

# 4. Check system pods
kubectl get pods -n kube-system
kubectl get pods -n kube-system | grep -v Running

# 5. Check cluster add-ons
aws eks list-addons --cluster-name <cluster-name>
aws eks describe-addon --cluster-name <cluster-name> --addon-name <addon>

# Red flags:
# - Nodes NotReady
# - System pods CrashLoopBackOff
# - API server unreachable
```

### 🔍 Phase 3: CHECK THE RESOURCE (10 min)
**Investigate the specific resource having issues.**

#### For Pods:
```bash
# 1. Get pod status
kubectl get pods -n <namespace>
kubectl get pod <pod-name> -n <namespace> -o wide

# 2. Describe pod (MOST IMPORTANT)
kubectl describe pod <pod-name> -n <namespace>
# Look for:
# - Events section (bottom)
# - Image pull errors
# - Resource limits
# - Node placement issues

# 3. Check logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # Previous container
kubectl logs <pod-name> -n <namespace> -c <container-name>  # Specific container

# 4. Check resource usage
kubectl top pod <pod-name> -n <namespace>

# 5. Execute into pod (if running)
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
# Then test connectivity, check files, etc.
```

#### For Deployments:
```bash
# 1. Check deployment status
kubectl get deployment <name> -n <namespace>
kubectl describe deployment <name> -n <namespace>

# 2. Check ReplicaSet
kubectl get rs -n <namespace>
kubectl describe rs <replicaset-name> -n <namespace>

# 3. Check rollout status
kubectl rollout status deployment/<name> -n <namespace>
kubectl rollout history deployment/<name> -n <namespace>

# 4. Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

#### For Services:
```bash
# 1. Check service
kubectl get svc <service-name> -n <namespace>
kubectl describe svc <service-name> -n <namespace>

# 2. Check endpoints
kubectl get endpoints <service-name> -n <namespace>
# Should list pod IPs; if empty, selector mismatch

# 3. Test service DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup <service-name>.<namespace>.svc.cluster.local

# 4. Test connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -O- <service-name>.<namespace>:<port>
```

#### For Ingress/LoadBalancer:
```bash
# 1. Check Ingress
kubectl get ingress -n <namespace>
kubectl describe ingress <name> -n <namespace>

# 2. Check Ingress controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# 3. Check AWS Load Balancer
aws elbv2 describe-load-balancers
aws elbv2 describe-target-groups
aws elbv2 describe-target-health --target-group-arn <arn>

# 4. Check security groups
aws ec2 describe-security-groups --group-ids <sg-id>
```

### 🔍 Phase 4: CHECK CONFIGURATION (10 min)
**Verify YAML/Helm/Terraform configuration.**

```bash
# 1. Get current manifest
kubectl get <resource> <name> -n <namespace> -o yaml > current.yaml

# 2. Check for typos, incorrect values
cat current.yaml

# 3. Validate manifest (dry-run)
kubectl apply -f manifest.yaml --dry-run=server

# 4. Compare with working version
kubectl diff -f manifest.yaml

# 5. Check ConfigMaps/Secrets
kubectl get configmap -n <namespace>
kubectl describe configmap <name> -n <namespace>
kubectl get secret <name> -n <namespace> -o yaml

# Common issues:
# - Typo in image name
# - Wrong namespace
# - Missing environment variables
# - Incorrect resource limits
# - Wrong service selector
```

### 🔍 Phase 5: CHECK PERMISSIONS (10 min)
**Verify IAM and RBAC.**

#### IAM (for AWS resources):
```bash
# 1. Check OIDC provider
aws iam list-open-id-connect-providers
aws eks describe-cluster --name <cluster> --query 'cluster.identity.oidc.issuer'

# 2. Check IAM role
aws iam get-role --role-name <role-name>
aws iam list-attached-role-policies --role-name <role-name>
aws iam get-policy-version --policy-arn <arn> --version-id <version>

# 3. Check service account annotation
kubectl get sa <service-account> -n <namespace> -o yaml
# Should have: eks.amazonaws.com/role-arn

# 4. Check pod identity (if using)
aws eks list-pod-identity-associations --cluster-name <cluster>
aws eks describe-pod-identity-association --cluster-name <cluster> --association-id <id>

# 5. Test AWS permissions from pod
kubectl exec -it <pod-name> -n <namespace> -- aws sts get-caller-identity
kubectl exec -it <pod-name> -n <namespace> -- aws s3 ls  # Test specific permission
```

#### RBAC (for Kubernetes resources):
```bash
# 1. Check service account
kubectl get sa <service-account> -n <namespace>

# 2. Check role/rolebinding
kubectl get role,rolebinding -n <namespace>
kubectl describe role <role-name> -n <namespace>
kubectl describe rolebinding <binding-name> -n <namespace>

# 3. Check clusterrole/clusterrolebinding
kubectl get clusterrole,clusterrolebinding | grep <keyword>
kubectl describe clusterrole <role-name>

# 4. Test permissions (auth can-i)
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<namespace>:<sa-name>
# Example:
kubectl auth can-i get pods --as=system:serviceaccount:default:my-sa

# Common issues:
# - Service account missing
# - Role missing required permissions
# - RoleBinding pointing to wrong service account
# - IAM role not trusted by OIDC provider
```

### 🔍 Phase 6: CHECK NETWORKING (15 min)
**Verify pod-to-pod, pod-to-service, external connectivity.**

```bash
# 1. Check pod IP and node
kubectl get pod <pod-name> -n <namespace> -o wide

# 2. Check CNI (Cilium/AWS VPC CNI)
# For Cilium:
cilium status
cilium connectivity test

# For AWS VPC CNI:
kubectl get pods -n kube-system -l k8s-app=aws-node
kubectl logs -n kube-system -l k8s-app=aws-node --tail=50

# 3. Check DNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Test DNS from pod:
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup <service-name>.<namespace>.svc.cluster.local

# 4. Check NetworkPolicies
kubectl get networkpolicy -n <namespace>
kubectl describe networkpolicy <name> -n <namespace>

# 5. Test connectivity
# Pod to pod:
kubectl exec -it <pod-a> -n <namespace> -- ping <pod-b-ip>
kubectl exec -it <pod-a> -n <namespace> -- curl <pod-b-ip>:<port>

# Pod to service:
kubectl exec -it <pod> -n <namespace> -- curl <service-name>:<port>

# Pod to external:
kubectl exec -it <pod> -n <namespace> -- curl https://google.com

# 6. Check security groups (for external access)
aws ec2 describe-security-groups --filters "Name=tag:kubernetes.io/cluster/<cluster-name>,Values=owned"

# Common issues:
# - NetworkPolicy blocking traffic
# - Security group too restrictive
# - DNS not resolving
# - CNI plugin issues
# - IP address exhaustion
```

### 🔍 Phase 7: CHECK RESOURCES (10 min)
**Verify CPU/Memory/Storage.**

```bash
# 1. Check node resources
kubectl top nodes
kubectl describe node <node-name> | grep -A 5 "Allocated resources"

# 2. Check pod resources
kubectl top pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Limits\|Requests"

# 3. Check for evictions
kubectl get events -n <namespace> | grep Evicted
kubectl get pods -n <namespace> | grep Evicted

# 4. Check PVC (if using storage)
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>

# 5. Check for resource pressure
kubectl describe node <node-name> | grep "Pressure"
# Look for: MemoryPressure, DiskPressure, PIDPressure

# Common issues:
# - OOMKilled (out of memory)
# - CPU throttling
# - Disk full
# - PVC not binding
# - Resource requests too high (pod can't be scheduled)
```

---

## 🛠️ TOOL-SPECIFIC TROUBLESHOOTING

### 🔧 Cilium (CNI)

```bash
# 1. Check status
cilium status

# 2. Check connectivity
cilium connectivity test

# 3. Check network policies
cilium policy get <id>

# 4. Check Hubble (observability)
cilium hubble ui
hubble observe

# 5. Check logs
kubectl logs -n kube-system -l k8s-app=cilium --tail=100

# Common issues:
# - CNI not installed properly
# - IP address pool exhausted
# - Network policy too restrictive
# - eBPF map errors

# Fixes:
# Restart Cilium pods:
kubectl rollout restart daemonset/cilium -n kube-system

# Check IP pool:
cilium status | grep "IP allocation"
```

### 🔧 Prometheus/Grafana

```bash
# 1. Check pods
kubectl get pods -n monitoring

# 2. Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open: http://localhost:9090/targets

# 3. Check ServiceMonitors
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor <name> -n monitoring

# 4. Check Grafana datasources
kubectl exec -n monitoring <grafana-pod> -- curl localhost:3000/api/datasources

# 5. Check logs
kubectl logs -n monitoring <prometheus-pod> --tail=100
kubectl logs -n monitoring <grafana-pod> --tail=100

# Common issues:
# - Targets down (check ServiceMonitor selectors)
# - Grafana can't connect to Prometheus (check datasource URL)
# - High memory usage (reduce retention or increase limits)
# - Missing metrics (ServiceMonitor not created)

# Fixes:
# Reload Prometheus config:
kubectl exec -n monitoring <prometheus-pod> -- curl -X POST localhost:9090/-/reload

# Check ServiceMonitor labels match:
kubectl get servicemonitor -n monitoring -o yaml | grep -A 3 selector
```

### 🔧 Loki

```bash
# 1. Check pods
kubectl get pods -n monitoring -l app=loki

# 2. Check Promtail (log shipper)
kubectl get pods -n monitoring -l app=promtail
kubectl logs -n monitoring -l app=promtail --tail=50

# 3. Test Loki query
kubectl exec -n monitoring <loki-pod> -- wget -qO- 'http://localhost:3100/loki/api/v1/query?query={namespace="default"}'

# 4. Check in Grafana
# Grafana → Explore → Select Loki datasource → Query: {namespace="default"}

# Common issues:
# - Promtail not collecting logs (check DaemonSet)
# - Loki storage full
# - Grafana can't connect to Loki
# - High cardinality labels

# Fixes:
# Restart Promtail:
kubectl rollout restart daemonset/promtail -n monitoring

# Check Loki storage:
kubectl exec -n monitoring <loki-pod> -- df -h
```

### 🔧 ArgoCD

```bash
# 1. Check pods
kubectl get pods -n argocd

# 2. Check application status
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd

# 3. Check sync status
argocd app get <app-name>
argocd app sync <app-name>

# 4. Check logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# 5. Check repository access
argocd repo list
argocd repo get <repo-url>

# Common issues:
# - Application OutOfSync (manifests changed)
# - Repository authentication failure
# - Sync failed (invalid manifest)
# - Resource hooks failing

# Fixes:
# Force sync:
argocd app sync <app-name> --force

# Reset application:
argocd app delete <app-name>
argocd app create -f application.yaml

# Check repo credentials:
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository
```

### 🔧 Istio

```bash
# 1. Check control plane
kubectl get pods -n istio-system
istioctl version

# 2. Check proxy status
istioctl proxy-status

# 3. Check sidecar injection
kubectl get namespace <namespace> -o yaml | grep istio-injection
kubectl get pods -n <namespace> -o jsonpath='{.items[*].spec.containers[*].name}'
# Should see: istio-proxy

# 4. Check VirtualServices/DestinationRules
kubectl get virtualservice -n <namespace>
kubectl describe virtualservice <name> -n <namespace>
kubectl get destinationrule -n <namespace>

# 5. Check mTLS
istioctl authn tls-check <pod-name>.<namespace>

# 6. Check logs
kubectl logs -n <namespace> <pod-name> -c istio-proxy

# 7. Use Kiali (service mesh dashboard)
istioctl dashboard kiali

# Common issues:
# - Sidecar not injected (namespace not labeled)
# - mTLS breaking communication
# - VirtualService routing wrong
# - High latency (check Envoy config)

# Fixes:
# Enable sidecar injection:
kubectl label namespace <namespace> istio-injection=enabled

# Restart pods to inject sidecar:
kubectl rollout restart deployment/<name> -n <namespace>

# Debug Envoy config:
istioctl proxy-config routes <pod-name>.<namespace>
istioctl proxy-config clusters <pod-name>.<namespace>

# Check Envoy stats:
kubectl exec -n <namespace> <pod-name> -c istio-proxy -- curl localhost:15000/stats
```

### 🔧 Kyverno

```bash
# 1. Check pods
kubectl get pods -n kyverno

# 2. Check policies
kubectl get clusterpolicy
kubectl get policy -n <namespace>
kubectl describe clusterpolicy <policy-name>

# 3. Check policy reports
kubectl get policyreport -A
kubectl describe policyreport <report-name> -n <namespace>

# 4. Test policy
kubectl apply -f test-resource.yaml --dry-run=server

# 5. Check logs
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno

# Common issues:
# - Policy blocking valid resources
# - Policy in wrong namespace
# - Validation vs mutation conflict
# - Webhook timeout

# Fixes:
# Disable policy temporarily:
kubectl patch clusterpolicy <policy-name> -p '{"spec":{"validationFailureAction":"audit"}}'

# Check webhook
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations

# Delete and recreate webhook:
kubectl delete validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg
kubectl rollout restart deployment/kyverno -n kyverno
```

### 🔧 Argo Rollouts

```bash
# 1. Check rollout status
kubectl get rollout -n <namespace>
kubectl describe rollout <name> -n <namespace>

# 2. Check rollout progress
kubectl argo rollouts get rollout <name> -n <namespace> --watch

# 3. Check analysis
kubectl get analysisrun -n <namespace>
kubectl describe analysisrun <name> -n <namespace>

# 4. Check canary services
kubectl get svc -n <namespace> | grep canary

# 5. Check Istio VirtualService (if using)
kubectl get virtualservice -n <namespace>

# 6. Check logs
kubectl logs -n argo-rollouts -l app.kubernetes.io/name=argo-rollouts

# Common issues:
# - Rollout stuck (analysis failing)
# - Traffic not splitting (VirtualService misconfigured)
# - Metrics provider unreachable
# - Analysis template invalid

# Fixes:
# Promote rollout manually:
kubectl argo rollouts promote <rollout-name> -n <namespace>

# Abort rollout:
kubectl argo rollouts abort <rollout-name> -n <namespace>

# Retry rollout:
kubectl argo rollouts retry <rollout-name> -n <namespace>

# Check traffic weights:
kubectl get virtualservice <name> -n <namespace> -o yaml | grep weight
```

---

## 🚨 COMMON ISSUE PATTERNS & QUICK FIXES

### 1. **Pod Stuck in Pending**

```bash
# Symptom: Pod in Pending state
kubectl get pods -n <namespace>

# Diagnosis:
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 Events

# Common causes:
# - Insufficient resources
# - PVC not binding
# - Node selector mismatch
# - Taints/tolerations

# Fix insufficient resources:
kubectl describe node <node-name> | grep -A 10 "Allocated resources"
# Solution: Add nodes or reduce resource requests

# Fix PVC not binding:
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>
# Solution: Check StorageClass exists, EBS volume available

# Fix node selector:
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 5 nodeSelector
kubectl get nodes --show-labels
# Solution: Add label to node or remove nodeSelector
```

### 2. **Pod Stuck in CrashLoopBackOff**

```bash
# Symptom: Pod keeps restarting
kubectl get pods -n <namespace>

# Diagnosis:
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
kubectl describe pod <pod-name> -n <namespace>

# Common causes:
# - Application error
# - Missing ConfigMap/Secret
# - Liveness probe failing
# - OOMKilled

# Fix application error:
# Check logs for error messages
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
# Debug inside container

# Fix missing ConfigMap/Secret:
kubectl get configmap -n <namespace>
kubectl get secret -n <namespace>
# Solution: Create missing resources

# Fix liveness probe:
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 10 livenessProbe
# Solution: Adjust probe settings or fix application health endpoint

# Fix OOMKilled:
kubectl describe pod <pod-name> -n <namespace> | grep -i oom
# Solution: Increase memory limits
```

### 3. **ImagePullBackOff**

```bash
# Symptom: Can't pull container image
kubectl describe pod <pod-name> -n <namespace>

# Common causes:
# - Image doesn't exist
# - Wrong image tag
# - Private registry auth missing
# - Rate limit (Docker Hub)

# Fix wrong image:
kubectl get pod <pod-name> -n <namespace> -o yaml | grep image:
# Solution: Correct image name/tag

# Fix private registry auth:
kubectl get secret -n <namespace> | grep docker
# Create imagePullSecret:
kubectl create secret docker-registry regcred \
  --docker-server=<registry> \
  --docker-username=<username> \
  --docker-password=<password> \
  -n <namespace>

# Add to pod spec:
# imagePullSecrets:
#   - name: regcred

# Fix rate limit:
# Solution: Use ECR or authenticated Docker Hub
```

### 4. **Service Not Reachable**

```bash
# Symptom: Can't access service
kubectl get svc <service-name> -n <namespace>

# Diagnosis:
# 1. Check endpoints
kubectl get endpoints <service-name> -n <namespace>
# If empty: selector doesn't match pods

# 2. Check pod labels
kubectl get pods -n <namespace> --show-labels
kubectl get svc <service-name> -n <namespace> -o yaml | grep -A 5 selector
# Solution: Fix selector to match pod labels

# 3. Test DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup <service-name>.<namespace>.svc.cluster.local

# 4. Test connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- curl <service-name>.<namespace>:<port>

# 5. Check NetworkPolicy
kubectl get networkpolicy -n <namespace>
# Solution: Add egress/ingress rules
```

### 5. **High Memory/CPU Usage**

```bash
# Symptom: Node or pod using too many resources
kubectl top nodes
kubectl top pods -n <namespace>

# Diagnosis:
kubectl describe node <node-name>
kubectl describe pod <pod-name> -n <namespace>

# Fix resource limits:
# Edit deployment:
kubectl edit deployment <name> -n <namespace>
# Add/adjust:
# resources:
#   requests:
#     memory: "256Mi"
#     cpu: "250m"
#   limits:
#     memory: "512Mi"
#     cpu: "500m"

# Fix memory leak:
# Check application logs for memory issues
kubectl logs <pod-name> -n <namespace> | grep -i memory

# Add node:
# If cluster-wide resource pressure
aws eks update-nodegroup-config \
  --cluster-name <cluster> \
  --nodegroup-name <nodegroup> \
  --scaling-config minSize=3,maxSize=10,desiredSize=5
```

### 6. **DNS Resolution Failing**

```bash
# Symptom: nslookup fails, services can't find each other
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Diagnosis:
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Fix CoreDNS:
kubectl rollout restart deployment/coredns -n kube-system

# Check CoreDNS ConfigMap:
kubectl get configmap coredns -n kube-system -o yaml

# Fix DNS policy:
kubectl get pod <pod-name> -n <namespace> -o yaml | grep dnsPolicy
# Should be: ClusterFirst (default)
```

### 7. **Deployment Stuck in Rollout**

```bash
# Symptom: Deployment not progressing
kubectl rollout status deployment/<name> -n <namespace>

# Diagnosis:
kubectl describe deployment <name> -n <namespace>
kubectl get rs -n <namespace>
kubectl describe rs <replicaset-name> -n <namespace>

# Fix stuck rollout:
# Check for image pull errors, resource constraints, etc.
kubectl rollout undo deployment/<name> -n <namespace>  # Rollback
kubectl rollout restart deployment/<name> -n <namespace>  # Force restart

# Set new image:
kubectl set image deployment/<name> <container>=<new-image> -n <namespace>

# Pause/resume:
kubectl rollout pause deployment/<name> -n <namespace>
kubectl rollout resume deployment/<name> -n <namespace>
```

---

## 📊 DEBUGGING TOOLS CHEAT SHEET

### Essential Tools to Install

```bash
# 1. kubectl (obviously)
brew install kubectl

# 2. kubectx/kubens (switch contexts/namespaces easily)
brew install kubectx

# 3. k9s (TUI for Kubernetes)
brew install k9s

# 4. stern (multi-pod log tailing)
brew install stern

# 5. Lens (GUI for Kubernetes)
# Download from: https://k8slens.dev/

# 6. kubetail (tail logs from multiple pods)
brew tap johanhaleby/kubetail && brew install kubetail

# 7. kube-capacity (check resource usage)
brew tap robscott/tap && brew install kube-capacity
```

### Quick Commands

```bash
# Watch resources in real-time
watch kubectl get pods -n <namespace>

# Tail logs from multiple pods
stern <pod-prefix> -n <namespace>
kubetail <deployment-name> -n <namespace>

# Interactive TUI
k9s

# Get resource usage across all namespaces
kube-capacity

# Port forward multiple ports
kubectl port-forward -n <namespace> <pod-name> 8080:80 9090:9090

# Copy files to/from pod
kubectl cp <pod-name>:/path/to/file ./local-file -n <namespace>
kubectl cp ./local-file <pod-name>:/path/to/file -n <namespace>

# Run debug pod with all network tools
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- /bin/bash

# Get all resources in namespace
kubectl get all -n <namespace>
kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n <namespace>
```

---

## 🔥 EMERGENCY QUICK REFERENCE

### "Pod won't start" - 30-second checklist
```bash
kubectl describe pod <pod> -n <ns> | tail -20  # Check events
kubectl logs <pod> -n <ns> --previous          # Check previous logs
kubectl get events -n <ns> --sort-by='.lastTimestamp' | tail
```

### "Service not working" - 30-second checklist
```bash
kubectl get endpoints <svc> -n <ns>                   # Check endpoints
kubectl get pods -n <ns> --show-labels                # Check labels
kubectl get svc <svc> -n <ns> -o yaml | grep selector # Check selector
```

### "Can't access externally" - 30-second checklist
```bash
kubectl get svc -n <ns> | grep LoadBalancer     # Check LB created
kubectl describe svc <svc> -n <ns> | grep Events # Check events
aws elbv2 describe-target-health --target-group-arn <arn>  # Check targets
```

### "High memory/CPU" - 30-second checklist
```bash
kubectl top nodes                        # Node usage
kubectl top pods -n <ns> --sort-by=memory # Pod usage
kubectl describe node <node> | grep -A 10 "Allocated resources"
```

---

## 🎓 BUILD YOUR TROUBLESHOOTING MUSCLE

### Practice Scenarios

1. **Deliberately break things:**
   - Change service selector
   - Remove IAM role annotation
   - Add wrong NetworkPolicy
   - Set memory limit too low
   - Then practice fixing

2. **Create a "break-fix" lab:**
   ```bash
   # Break DNS
   kubectl scale deployment/coredns -n kube-system --replicas=0
   # Fix it
   kubectl scale deployment/coredns -n kube-system --replicas=2
   ```

3. **Time yourself:**
   - Can you find and fix a broken service in under 5 minutes?
   - Can you diagnose a CrashLoopBackOff in under 2 minutes?

4. **Document your fixes:**
   - Keep a "runbook" of issues you've solved
   - Write down the exact commands that worked

---

## 🎯 TROUBLESHOOTING MINDSET

### Good Habits:
✅ Always check logs first
✅ Use `describe` liberally
✅ Follow the data path (request → ingress → service → pod)
✅ Change ONE thing at a time
✅ Document what you tried
✅ Check recent changes (Git, Terraform, Helm)

### Bad Habits:
❌ Randomly restarting things
❌ Changing multiple things at once
❌ Not checking logs
❌ Assuming it's "just Kubernetes being weird"
❌ Not verifying fixes
❌ Skipping the describe command

---

## 📖 RESOURCES TO BOOKMARK

- **Official Docs:** https://kubernetes.io/docs/tasks/debug/
- **EKS Troubleshooting:** https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html
- **Kubernetes Patterns:** https://k8spatterns.io/
- **EKS Best Practices:** https://aws.github.io/aws-eks-best-practices/
- **Debugging Techniques:** https://learnk8s.io/troubleshooting-deployments

---

## 🎯 SUMMARY

**The Universal Process:**
1. **Context** → What's broken? What changed?
2. **Cluster Health** → Is infrastructure OK?
3. **Resource Check** → Describe, logs, status
4. **Configuration** → Is YAML correct?
5. **Permissions** → IAM, RBAC OK?
6. **Networking** → Can pods communicate?
7. **Resources** → CPU/memory sufficient?

**Tool-Specific:**
- Each tool has its own commands
- But the PATTERN is the same: logs → describe → test → fix

**Practice:**
- Break things deliberately
- Time yourself
- Build runbooks
- Learn the patterns

**Remember:**
> "90% of issues are: wrong config, missing permissions, or networking."
> Check these three first, save hours.

---

Need help debugging a specific issue right now? Tell me:
1. What's the symptom?
2. What tool/resource is affected?
3. Any error messages?

I'll walk you through the diagnosis step-by-step! 🚀
