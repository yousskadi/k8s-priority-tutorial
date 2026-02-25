# Module 02 — API Priority & Fairness (APF)

## 🎯 Ce que tu vas apprendre

- Comprendre les objets `FlowSchema` et `PriorityLevelConfiguration`
- Observer le throttling de l'API server
- Créer des règles APF custom pour protéger les requêtes critiques
- Diagnostiquer avec les métriques APF

---

## 🧩 Théorie (10 min)

### Le problème sans APF

```
kube-apiserver reçoit 1000 req/s
├── 300 req/s : kube-controller-manager (CRITIQUE)
├── 200 req/s : scheduler (CRITIQUE)  
├── 400 req/s : operators custom (important)
└── 100 req/s : kubectl des devs (peut attendre)

Sans APF → tout est mélangé → risque que les controllers système
soient throttlés par des operators mal configurés !
```

### Architecture APF

```
Requête entrante
      ↓
  FlowSchema matching (par ordre de priorité numérique)
      ↓
  PriorityLevelConfiguration assignée
      ↓
  File d'attente (queue) avec seats limités
      ↓
  Exécution ou HTTP 429 (Too Many Requests)
```

### FlowSchema

Définit **qui** → **quelle priorité**.  
Match sur : user, group, serviceaccount, verbe, resource, namespace.

```yaml
# Exemple : toutes les requêtes du namespace "production" → workload-high
spec:
  priorityLevelConfiguration:
    name: workload-high
  matchingPrecedence: 1000  # plus petit = matché en premier
  rules:
  - subjects:
    - kind: ServiceAccount
      serviceAccount:
        namespace: production
    resourceRules:
    - verbs: ["*"]
      resources: ["*"]
```

### PriorityLevelConfiguration

Définit **combien de requêtes** peuvent s'exécuter en parallèle.

```yaml
spec:
  type: Limited
  limited:
    nominalConcurrencyShares: 30  # "poids" relatif des seats
    lendingLimit: 10              # seats qu'on peut prêter aux autres
    borrowingLimit: 10            # seats qu'on peut emprunter
    limitResponse:
      type: Queue
      queuing:
        queues: 64        # nombre de files
        handSize: 6       # répartition par flow
        queueLengthLimit: 50  # max requêtes en attente par queue
```

### Types de PriorityLevel

| Type | Description |
|------|-------------|
| `exempt` | Jamais throttlé (kube-system, leader controllers) |
| `Limited` | Throttlé selon `nominalConcurrencyShares` |
| `reject` | Toujours rejeté immédiatement (blacklist) |

---

## 🧪 Lab 1 : Observer les FlowSchemas existants

```bash
# Voir toutes les FlowSchemas (triées par priorité)
kubectl get flowschemas --sort-by='.spec.matchingPrecedence'

# Voir les PriorityLevelConfigurations
kubectl get prioritylevelconfigurations

# Voir les détails d'une FlowSchema
kubectl describe flowschema catch-all
kubectl describe flowschema system-leader-election
```

Résultat attendu pour les FlowSchemas par défaut :
```
NAME                           PRIORITYLEVEL     MATCHINGPRECEDENCE
exempt                         exempt            1
probes                         exempt            2
system-leader-election         leader-election   100
kube-system-service-accounts   workload-high     900
system-service-accounts        workload-low      9000
global-default                 global-default    9900
catch-all                      catch-all         10000
```

---

## 🧪 Lab 2 : Inspecter les métriques APF

```bash
# Port-forward vers l'API server (nécessite accès au control-plane)
# Dans kind, utiliser le kubeconfig directement

# Métriques APF
kubectl get --raw /metrics | grep apiserver_flowcontrol

# Métriques clés :
# apiserver_flowcontrol_current_inqueue_requests     → requêtes en attente
# apiserver_flowcontrol_dispatched_requests_total    → requêtes traitées
# apiserver_flowcontrol_rejected_requests_total      → requêtes rejetées (429)
# apiserver_flowcontrol_current_executing_requests   → en cours d'exécution
```

---

## 🧪 Lab 3 : Créer un PriorityLevel custom

```bash
# Créer un niveau de priorité pour nos workloads custom
kubectl apply -f manifests/02-priority-level-custom.yaml

# Créer une FlowSchema qui route le namespace "demo" vers ce niveau
kubectl apply -f manifests/01-flow-schema-custom.yaml

# Vérifier
kubectl get flowschemas
kubectl get prioritylevelconfigurations
```

---

## 🧪 Lab 4 : Observer le throttling

```bash
# Créer le namespace de test
kubectl create namespace demo

# Simuler beaucoup de requêtes depuis le namespace demo
# (utilise un pod avec kubectl)
kubectl apply -f manifests/03-test-throttling.yaml

# Observer les métriques pendant le test
watch -n1 "kubectl get --raw /metrics | grep apiserver_flowcontrol_rejected | grep demo-priority"
```

---

## 🔍 Diagnostic APF

```bash
# Voir si des requêtes sont rejetées
kubectl get --raw /metrics | grep 'apiserver_flowcontrol_rejected_requests_total' | grep -v '^#'

# Voir la "santé" des FlowSchemas
kubectl get flowschemas -o custom-columns='NAME:.metadata.name,PRIORITY:.spec.priorityLevelConfiguration.name,PRECEDENCE:.spec.matchingPrecedence,SCHEMA_CONDITION:.status.conditions[0].type'

# Identifier quelle FlowSchema match une requête
# (via les logs de l'API server)
kubectl logs -n kube-system -l component=kube-apiserver | grep flowcontrol
```

---

## ✅ Points clés CKS

1. APF remplace `--max-requests-inflight` et `--max-mutating-requests-inflight` (deprecated)
2. Les objets APF sont **cluster-scoped** et gérés par Kubernetes
3. `matchingPrecedence` : **plus petit = priorité plus haute** pour le matching
4. `exempt` = jamais throttlé (utilisé pour le scheduler et controller-manager)
5. Le `catch-all` FlowSchema est le filet de sécurité (priorité 10000)

---

## 🧹 Cleanup

```bash
kubectl delete -f manifests/
kubectl delete namespace demo
```
