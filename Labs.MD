# 🧪 Guide pas à pas — Labs reproductibles

> **Tout ce dont tu as besoin est ici.**
> Chaque étape est une commande à copier-coller dans ton terminal.
> Les labs sont indépendants : tu peux faire lab01 sans lab02.

---

## ✅ Prérequis — Vérifie avant de commencer

```bash
# Vérifier que tout est installé
make check-deps

# Si make n'est pas dispo, vérification manuelle :
kind version      # doit répondre
kubectl version --client
```

Installation rapide si manquant :
```bash
# kind
brew install kind          # macOS
# ou
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
chmod +x kind && sudo mv kind /usr/local/bin/

# kubectl
brew install kubectl       # macOS
# ou
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

---

## 🔵 LAB 01 — Pod Priority & Preemption

**Ce que tu vas voir :** un pod critique éjecte des pods batch pour obtenir des ressources.

### Option A — Automatique (tout d'un coup)

```bash
make lab01
```

### Option B — Pas à pas (recommandé pour apprendre)

#### Étape 1 : Créer le cluster

```bash
cat <<EOF | kind create cluster --name lab01 --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

kubectl config use-context kind-lab01
kubectl get nodes   # attends que tous soient Ready
```

#### Étape 2 : Créer les PriorityClasses

```bash
kubectl apply -f 01-pod-priority/manifests/00-priority-classes.yaml

# Vérifie
kubectl get priorityclasses
```

**Ce que tu dois voir :**
```
NAME                      VALUE        GLOBAL-DEFAULT
high-priority             1000000      false
high-priority-no-preempt  900000       false
low-priority              100000       true            ← globalDefault
medium-priority           500000       false
system-cluster-critical   2000000000   false
system-node-critical      2000001000   false
```

**Question d'audit :** *Pourquoi `low-priority` est `globalDefault: true` ?*
→ Tout pod sans `priorityClassName` hérite automatiquement de `low-priority`.
→ Protège le cluster : un dev qui oublie la priorityClass ne bloque pas la production.

#### Étape 3 : Remplir le cluster (batch pods)

```bash
kubectl apply -f 01-pod-priority/manifests/01-low-priority-pods.yaml

# Observer les pods qui démarrent
kubectl get pods -w
# Ctrl+C pour arrêter le watch
```

#### Étape 4 : Déployer le pod critique → PRÉEMPTION

```bash
# Dans un terminal : surveille en temps réel
kubectl get pods -w &

# Dans le même terminal : déploie le pod critique
kubectl apply -f 01-pod-priority/manifests/02-high-priority-pod.yaml
```

**Ce que tu dois voir en temps réel :**
```
batch-job-filler-xxx   Running  → Terminating   ← éjecté !
batch-job-filler-yyy   Running  → Terminating   ← éjecté !
payment-api-critical   Pending  → Running        ← schedulé !
```

#### Étape 5 : Analyser les events

```bash
# Tuer le watch en arrière-plan
kill %1 2>/dev/null

# Voir les events de préemption
kubectl get events --sort-by='.lastTimestamp' | grep -iE 'preempt|evict'

# Voir la priorité effective du pod critique
kubectl get pod payment-api-critical -o jsonpath='{.spec.priority}'
# → 1000000
```

#### Étape 6 : Tester preemptionPolicy: Never

```bash
kubectl apply -f 01-pod-priority/manifests/03-guaranteed-system-pod.yaml

# Ce pod a value=900000 mais preemptionPolicy=Never
# Il sera dans la queue en haute priorité mais N'ÉJECTERA PAS les pods en cours
kubectl describe pod reporting-job-no-preempt | grep -E "Priority|Preemption"
```

**Différence clé :**
```
high-priority (1000000, PreemptLowerPriority) → éjecte des pods pour s'installer
high-priority-no-preempt (900000, Never)      → attend poliment dans la queue
```

#### Cleanup lab01

```bash
kind delete cluster --name lab01
```

---

## 🟡 LAB 02 — API Priority & Fairness

**Ce que tu vas voir :** comment les requêtes à l'API server sont classées et throttlées.

### Option A — Automatique

```bash
make lab02
```

### Option B — Pas à pas

#### Étape 1 : Créer le cluster

```bash
cat <<EOF | kind create cluster --name lab02 --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
EOF

kubectl config use-context kind-lab02
```

#### Étape 2 : Observer les FlowSchemas existants

```bash
# Voir toutes les FlowSchemas dans l'ordre de matching
kubectl get flowschemas --sort-by='.spec.matchingPrecedence' \
  -o custom-columns='NAME:.metadata.name,PRIORITY-LEVEL:.spec.priorityLevelConfiguration.name,PRECEDENCE:.spec.matchingPrecedence'
```

**Ce que tu dois voir :**
```
NAME                           PRIORITY-LEVEL     PRECEDENCE
exempt                         exempt             1          ← scheduler, controller-manager
probes                         exempt             2
system-leader-election         leader-election    100
...
global-default                 global-default     9900
catch-all                      catch-all          10000      ← filet de sécurité
```

**Question d'audit :** *Que se passe-t-il si une requête ne matche aucune FlowSchema ?*
→ Elle tombe dans `catch-all` (precedence 10000), le niveau le plus throttlé.

```bash
# Voir les PriorityLevelConfigurations
kubectl get prioritylevelconfigurations

# Détail d'un niveau
kubectl describe prioritylevelconfiguration workload-low
```

#### Étape 3 : Créer les PriorityLevels custom (AVANT les FlowSchemas)

```bash
# ⚠️ L'ordre est important : PriorityLevels d'abord
kubectl apply -f 02-api-priority-fairness/manifests/02-priority-level-custom.yaml

# Vérifier
kubectl get prioritylevelconfigurations | grep demo
```

**Ce que tu dois voir :**
```
demo-priority    Limited   ...
demo-restricted  Limited   ...
```

#### Étape 4 : Créer les FlowSchemas custom

```bash
kubectl apply -f 02-api-priority-fairness/manifests/01-flow-schema-custom.yaml

# Vérifier l'ordre de matching
kubectl get flowschemas --sort-by='.spec.matchingPrecedence' | grep demo
```

**Ce que tu dois voir :**
```
demo-restricted-sa   demo-restricted   4999   ← matché EN PREMIER
demo-workloads       demo-priority     5000
```

**Question d'audit :** *Pourquoi `demo-restricted-sa` a precedence 4999 et non 5001 ?*
→ On veut que le SA restreint soit isolé dans sa propre file AVANT que la règle générale
  `demo-workloads` le capture. Si on mettait 5001, `demo-workloads` (5000) le capturerait en premier.

#### Étape 5 : Vérifier qu'aucune FlowSchema n'est "Dangling"

```bash
# Une FlowSchema est "Dangling" quand elle pointe vers un PriorityLevel inexistant
kubectl get flowschemas -o json | \
  jq -r '.items[] | select(.status.conditions[]?.reason == "PriorityLevelNotFound") | .metadata.name'
# → doit retourner vide
```

#### Étape 6 : Tester le throttling

```bash
kubectl apply -f 02-api-priority-fairness/manifests/03-test-throttling.yaml

# Attendre 15s
sleep 15

# Voir les pods
kubectl get pods -n demo

# Logs du générateur normal
kubectl logs -n demo api-load-generator-normal --tail=20

# Logs du générateur restreint (devrait voir plus d'erreurs)
kubectl logs -n demo api-load-generator-restricted --tail=20
```

#### Étape 7 : Métriques APF

```bash
# Requêtes rejetées par niveau
kubectl get --raw /metrics | grep apiserver_flowcontrol_rejected | grep -v '#'

# Requêtes en attente dans les queues
kubectl get --raw /metrics | grep apiserver_flowcontrol_current_inqueue | grep -v '#'
```

#### Cleanup lab02

```bash
kind delete cluster --name lab02
```

---

## 🔴 LAB 03 — Scénario Production

**Ce que tu vas construire :** un cluster multi-tenant complet avec priorités alignées sur les SLAs.

### Option A — Automatique

```bash
make lab03          # setup complet
make lab03-preempt  # simule un incident
```

### Option B — Pas à pas

#### Étape 1 : Créer le cluster (3 workers)

```bash
cat <<EOF | kind create cluster --name lab03 --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
EOF

kubectl config use-context kind-lab03
kubectl get nodes   # doit avoir 3 workers
```

#### Étape 2 : Namespaces et ResourceQuotas

```bash
kubectl apply -f 03-production-like/manifests/00-namespaces.yaml

kubectl get namespaces | grep -E "production|staging|batch"
kubectl get resourcequota -A
```

#### Étape 3 : PriorityClasses alignées SLA

```bash
kubectl apply -f 03-production-like/manifests/01-priority-classes.yaml

kubectl get priorityclasses | grep -v system
```

**Ce que tu dois voir :**
```
NAME          VALUE     GLOBAL-DEFAULT
batch         100000    false
critical      1000000   false
development   10000     false
high          800000    false
standard      500000    true     ← défaut pour tout pod sans priorityClassName
```

#### Étape 4 : APF (ordre obligatoire)

```bash
# 1. PriorityLevels D'ABORD
kubectl apply -f 03-production-like/manifests/06-apf-priority-levels.yaml

# 2. FlowSchemas ENSUITE
kubectl apply -f 03-production-like/manifests/05-apf-flow-schemas.yaml

# Vérifier
kubectl get flowschemas | grep -E "production-|staging-|batch-"
```

#### Étape 5 : Déployer les workloads

```bash
# Critiques (production)
kubectl apply -f 03-production-like/manifests/02-critical-workloads.yaml

# Attendre le rollout
kubectl rollout status deployment/payment-api -n production
kubectl rollout status deployment/auth-service -n production

# Standard (staging)
kubectl apply -f 03-production-like/manifests/03-standard-workloads.yaml

# Batch
kubectl apply -f 03-production-like/manifests/04-batch-workloads.yaml
```

#### Étape 6 : Vérifier les PDB

```bash
kubectl get pdb -n production
```

**Ce que tu dois voir :**
```
NAME              MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS
auth-service-pdb  1               N/A               1
payment-api-pdb   2               N/A               1
```

**Question d'audit :** *Que se passe-t-il si on essaie de drainer un nœud avec tous les payment-api ?*
→ `kubectl drain` sera bloqué car le PDB exige `minAvailable: 2`.

#### Étape 7 : Scénario incident — Préemption

```bash
# Saturer le cluster avec des batch jobs
kubectl scale deployment data-pipeline -n batch --replicas=15

# Observer la saturation
kubectl get pods -n batch | tail -5
kubectl describe nodes | grep -A3 "Allocated resources"

# Déployer un pod d'urgence critique
kubectl run incident-response \
  --image=nginx:alpine \
  --namespace=production \
  --overrides='{"spec":{"priorityClassName":"critical","containers":[{"name":"incident-response","image":"nginx:alpine","resources":{"requests":{"memory":"128Mi","cpu":"100m"}}}]}}'

# Surveiller
watch -n2 kubectl get pods -n production
# → incident-response doit passer Running après éjection de batch pods

# Events
kubectl get events -A --sort-by='.lastTimestamp' | grep -iE 'preempt|evict'
```

#### Étape 8 : Vérifier que la prod n'est pas impactée

```bash
# Les payment-api et auth-service doivent toujours tourner
kubectl get pods -n production

# Le PDB doit toujours être respecté
kubectl get pdb -n production
```

#### Cleanup lab03

```bash
kind delete cluster --name lab03
```

---

## 🧹 Cleanup global

```bash
# Supprimer tous les clusters du tutorial
make clean

# ou manuellement
kind delete cluster --name lab01
kind delete cluster --name lab02
kind delete cluster --name lab03

# Voir les clusters restants
kind get clusters
```

---

## 🔧 Tester localement avant de pusher

```bash
# Lint YAML (évite les erreurs CI)
make lint

# ou manuellement
find . -name "*.yaml" \
  -not -path "./.git/*" \
  -not -path "./.github/*" \
  -not -name ".yamllint.yaml" \
  | xargs yamllint -c .yamllint.yaml

# Si yamllint n'est pas installé
pip install yamllint
```

---

## ❓ Problèmes fréquents

| Problème | Cause | Solution |
|----------|-------|----------|
| Pod reste `Pending` | Cluster pas assez plein | `kubectl scale deployment batch-job-filler --replicas=20` |
| Pas de préemption | Pod critique a assez de ressources | Augmenter ses `requests` |
| FlowSchema `Dangling` | PriorityLevel créé après le FlowSchema | Supprimer et ré-appliquer dans le bon ordre |
| `kubectl: command not found` dans un pod | Mauvaise image | Utiliser `bitnami/kubectl` |
| kind cluster lent | Image à télécharger | La première fois prend ~3 min |
