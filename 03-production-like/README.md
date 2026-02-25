# Module 03 — Scénario Production

## 🎯 Ce que tu vas construire

Un cluster multi-tenant avec :
- 3 namespaces (`production`, `staging`, `batch`)
- PriorityClasses alignées avec les SLAs business
- FlowSchemas et PriorityLevels APF cohérents
- Monitoring de la priorité
- PodDisruptionBudgets pour les workloads critiques

---

## 🏗️ Architecture cible

```
┌─────────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER                        │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ production  │  │  staging    │  │       batch         │ │
│  │             │  │             │  │                     │ │
│  │ payment-api │  │ payment-api │  │  data-pipeline      │ │
│  │ priority:   │  │ priority:   │  │  priority:          │ │
│  │ critical    │  │ standard    │  │  batch              │ │
│  │ (1000000)   │  │ (500000)    │  │  (100000)           │ │
│  │             │  │             │  │                     │ │
│  │ APF:        │  │ APF:        │  │  APF:               │ │
│  │ prod-high   │  │ staging-std │  │  batch-low          │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │             kube-apiserver                           │   │
│  │  FlowSchemas (du plus prioritaire au moins) :        │   │
│  │  1  (exempt)    → scheduler, controller-manager      │   │
│  │  100 (exempt)   → kube-system leader-election        │   │
│  │  1000 (prod-high) → production ServiceAccounts       │   │
│  │  3000 (staging-std) → staging ServiceAccounts        │   │
│  │  5000 (batch-low) → batch ServiceAccounts            │   │
│  │  9900 (global-default) → tout le reste               │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 🧪 Setup complet

```bash
# 1. Créer le cluster kind avec 3 workers
cat <<EOF | kind create cluster --name prod-lab --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
EOF

# 2. Appliquer DANS L'ORDRE (les dépendances d'abord)
kubectl apply -f manifests/00-namespaces.yaml
kubectl apply -f manifests/01-priority-classes.yaml

# Attendre
sleep 2

kubectl apply -f manifests/06-apf-priority-levels.yaml  # Créer les PriorityLevels D'ABORD
kubectl apply -f manifests/05-apf-flow-schemas.yaml      # Puis les FlowSchemas

# Déployer les workloads
kubectl apply -f manifests/02-critical-workloads.yaml
kubectl apply -f manifests/03-standard-workloads.yaml
kubectl apply -f manifests/04-batch-workloads.yaml
```

---

## 🔬 Vérifications

```bash
# 1. Vérifier les priorités
kubectl get priorityclasses
kubectl get pods -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,PRIORITY:.spec.priorityClassName'

# 2. Vérifier les FlowSchemas
kubectl get flowschemas --sort-by='.spec.matchingPrecedence'

# 3. Simuler un cluster plein : scaler les batch jobs
kubectl scale deployment data-pipeline -n batch --replicas=20

# Attendre saturation
kubectl get pods -n batch -w

# 4. Déployer un pod critique pendant la saturation
kubectl run emergency-deploy \
  --image=nginx:alpine \
  --namespace=production \
  --overrides='{"spec":{"priorityClassName":"critical"}}'

# Observer la préemption
kubectl get events --sort-by='.lastTimestamp' -A | grep -E 'Preempt|evict'
```

---

## 📊 Monitoring

```bash
# PriorityClass de chaque pod en running
kubectl get pods -A -o json | jq -r '
  .items[] |
  [.metadata.namespace, .metadata.name, (.spec.priorityClassName // "none"), (.spec.priority | tostring)] |
  @tsv
' | column -t | sort -k3

# APF : voir les niveaux actifs
kubectl get --raw /metrics | grep apiserver_flowcontrol_current_executing | grep -v '#'

# Résumé par PriorityLevel
kubectl get --raw /metrics | \
  grep apiserver_flowcontrol_dispatched_requests_total | \
  grep -v '#' | \
  sort -t'"' -k4
```

---

## 🚨 Scénarios de test

### Scénario A : Incident production

```bash
# Simuler qu'un batch job consomme tout le cluster
kubectl scale deployment data-pipeline -n batch --replicas=50

# Voir le cluster saturé
kubectl get nodes
kubectl describe nodes | grep -A5 "Allocated resources"

# Déployer la réponse à l'incident (pod critique)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: incident-response
  namespace: production
spec:
  priorityClassName: critical
  containers:
  - name: fix
    image: nginx:alpine
    resources:
      requests:
        memory: "256Mi"
        cpu: "250m"
EOF

# Observer que les batch pods sont éjectés pour faire de la place
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

### Scénario B : Operator mal configuré

```bash
# Simuler un operator qui flood l'API server
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: bad-operator
  namespace: batch
spec:
  serviceAccountName: batch-sa
  containers:
  - name: flood
    image: bitnami/kubectl
    command: ["sh", "-c", "while true; do kubectl get pods -A; done"]
EOF

# Vérifier que la production n'est PAS impactée
kubectl get --raw /metrics | grep apiserver_flowcontrol_rejected | grep batch
# → Les rejets se concentrent sur batch-low, pas sur prod-high
```

---

## ✅ Checklist Production

- [ ] Toutes les apps critiques ont `priorityClassName: critical`
- [ ] Les jobs batch ont `priorityClassName: batch`  
- [ ] PodDisruptionBudgets définis pour les apps à haute priorité
- [ ] FlowSchemas testés pour ne pas throttler les controllers système
- [ ] Alertes sur `apiserver_flowcontrol_rejected_requests_total`
- [ ] `resourceQuota` par namespace pour éviter qu'un namespace prenne tout
- [ ] Review des `PriorityClass` dans les policies de sécurité (OPA/Kyverno)
