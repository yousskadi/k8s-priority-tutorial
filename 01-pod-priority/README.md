# Module 01 — Pod Priority & Preemption

## 🎯 Ce que tu vas apprendre

- Créer des `PriorityClass`
- Assigner une priorité à des pods
- Observer la **préemption** (éviction forcée)
- Comprendre `preemptionPolicy: Never`

---

## 🧩 Théorie (5 min)

### PriorityClass

Une `PriorityClass` est une ressource **cluster-scoped** (pas dans un namespace).  
Elle définit un **entier** de priorité : plus c'est grand, plus c'est prioritaire.

```
Plage valide : -2,147,483,648 à 1,000,000,000
Réservé système (>= 1,000,000,000) : system-cluster-critical, system-node-critical
```

### Cycle de vie d'un Pod avec Priority

```
1. Pod créé → scheduler regarde sa priorité
2. Si ressources disponibles → schedulé normalement
3. Si ressources insuffisantes :
   a. Cherche des pods avec priorité INFÉRIEURE sur des nœuds
   b. Si trouvé → éjecte ces pods (Preemption)
   c. Pod critique schedulé sur le nœud libéré
   d. Pods éjectés → reviennent en Pending et attendent
```

### preemptionPolicy

| Valeur | Comportement |
|--------|-------------|
| `PreemptLowerPriority` (défaut) | Peut éjecter des pods moins prioritaires |
| `Never` | Ne préempte pas — attend juste dans la queue |

---

## 🧪 Lab 1 : Setup du cluster

```bash
# Créer un cluster kind avec ressources limitées (simule un cluster plein)
cat <<EOF | kind create cluster --name priority-lab --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
  extraArgs:
    cpu: "2"
    memory: "2Gi"
- role: worker
  extraArgs:
    cpu: "2"
    memory: "2Gi"
EOF

kubectl cluster-info --context kind-priority-lab
```

---

## 🧪 Lab 2 : Créer les PriorityClasses

```bash
kubectl apply -f manifests/00-priority-classes.yaml

# Vérifier
kubectl get priorityclasses
```

Résultat attendu :
```
NAME                      VALUE        GLOBAL-DEFAULT   AGE
high-priority             1000000      false            5s
medium-priority           500000       false            5s
low-priority              100000       true             5s
system-cluster-critical   2000000000   false            ...
system-node-critical      2000001000   false            ...
```

---

## 🧪 Lab 3 : Remplir le cluster

```bash
# Déployer des pods low-priority pour saturer les workers
kubectl apply -f manifests/01-low-priority-pods.yaml

# Attendre qu'ils soient Running
kubectl get pods -w
```

---

## 🧪 Lab 4 : Observer la préemption

```bash
# Déployer un pod high-priority (nécessite plus de ressources qu'il n'en reste)
kubectl apply -f manifests/02-high-priority-pod.yaml

# Observer en temps réel
kubectl get pods -w
# → Les pods low-priority passent à Terminating
# → Le pod high-priority passe à Running

# Voir les events de préemption
kubectl get events --sort-by='.lastTimestamp' | grep -i preempt
```

---

## 🧪 Lab 5 : preemptionPolicy: Never

```bash
kubectl apply -f manifests/03-guaranteed-system-pod.yaml

# Ce pod a une haute priorité mais ne préempte PAS
# Il attendra que des ressources se libèrent naturellement
kubectl describe pod guaranteed-no-preempt | grep -A5 "Priority"
```

---

## ✅ Points clés à retenir pour le CKS

1. `PriorityClass` est **cluster-scoped** (pas namespaced)
2. `globalDefault: true` → s'applique aux pods sans `priorityClassName`
3. La préemption respecte le **PodDisruptionBudget** (PDB)
4. Les pods préemptés reçoivent un **graceful termination** (30s par défaut)
5. Un pod système avec `system-cluster-critical` ne sera jamais éjecté par tes workloads

---

## 🧹 Cleanup

```bash
kubectl delete -f manifests/
kind delete cluster --name priority-lab
```
