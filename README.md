# Kubernetes Priority & Fairness — Tutorial CKS/Production

> **Objectif** : Comprendre, expérimenter et maîtriser les deux mécanismes de priorité Kubernetes :
> 1. **Pod Priority & Preemption** — qui tourne sur les nœuds ?
> 2. **API Priority & Fairness (APF)** — qui peut parler à `kube-apiserver` ?

---

## 📚 Table des matières

| # | Module | Difficulté | Durée estimée |
|---|--------|-----------|---------------|
| 01 | [Pod Priority & Preemption](./01-pod-priority/) | ⭐ Débutant | 20 min |
| 02 | [API Priority & Fairness](./02-api-priority-fairness/) | ⭐⭐ Intermédiaire | 30 min |
| 03 | [Scénario Production](./03-production-like/) | ⭐⭐⭐ Avancé | 45 min |

---

## 🧠 Concepts Clés

### Problème 1 : Le cluster est plein — qui est éjecté ?

Imagine un cluster avec 3 nœuds. Des pods `monitoring`, `batch-job`, et `payment-api` tournent tous.
Un nouveau pod critique arrive mais il n'y a plus de ressources.

**Sans Pod Priority** → Kubernetes refuse le pod ou attend indéfiniment.  
**Avec Pod Priority** → Kubernetes éjecte le pod le moins prioritaire pour faire de la place.

```
[payment-api : priority=1000]  ← ne sera JAMAIS éjecté pour un job batch
[monitoring  : priority=500 ]  ← éjecté si besoin pour payment-api
[batch-job   : priority=100 ]  ← éjecté en premier
```

### Problème 2 : L'API server est surchargé — qui est throttlé ?

100 clients appellent l'API en même temps : des operators, des users, des controllers système.
Sans règles → tout le monde se bat, les controllers critiques peuvent être bloqués.

**API Priority & Fairness** partitionne les requêtes en files (FlowSchemas + PriorityLevelConfigurations).

```
[system-high   : 50 seats ] ← kube-controller-manager, scheduler
[workload-high : 40 seats ] ← leaders d'operators
[workload-low  : 100 seats] ← appels normaux
[catch-all     : 5 seats  ] ← tout le reste (throttlé fortement)
```

---

## 🚀 Prérequis

```bash
# Kind (local)
go install sigs.k8s.io/kind@latest
# ou
brew install kind

# kubectl
brew install kubectl

# hey (load testing HTTP)
brew install hey
# ou
go install github.com/rakyll/hey@latest

# kubectx / kubens (optionnel)
brew install kubectx
```

---

## 🗂️ Structure du repo

```
.
├── README.md
├── 01-pod-priority/
│   ├── README.md
│   └── manifests/
│       ├── 00-priority-classes.yaml
│       ├── 01-low-priority-pods.yaml
│       ├── 02-high-priority-pod.yaml
│       └── 03-guaranteed-system-pod.yaml
├── 02-api-priority-fairness/
│   ├── README.md
│   └── manifests/
│       ├── 00-check-apf.yaml
│       ├── 01-flow-schema-custom.yaml
│       ├── 02-priority-level-custom.yaml
│       └── 03-test-throttling.yaml
├── 03-production-like/
│   ├── README.md
│   └── manifests/
│       ├── 00-namespaces.yaml
│       ├── 01-priority-classes.yaml
│       ├── 02-critical-workloads.yaml
│       ├── 03-standard-workloads.yaml
│       ├── 04-batch-workloads.yaml
│       ├── 05-apf-flow-schemas.yaml
│       └── 06-apf-priority-levels.yaml
└── .github/
    └── workflows/
        ├── validate.yaml
        └── e2e-tests.yaml
```

---

## 🔑 Concepts CKS à retenir

| Concept | Ressource K8s | Scope |
|---------|--------------|-------|
| Pod Priority | `PriorityClass` | Cluster-wide |
| Preemption | `.spec.preemptionPolicy` | Par PriorityClass |
| APF Flow Schema | `FlowSchema` | Cluster-wide |
| APF Priority Level | `PriorityLevelConfiguration` | Cluster-wide |
| APF Exempt | `exempt` type | Cluster-wide |

---

## 📖 Lectures complémentaires

- [Pod Priority Docs](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)
- [API Priority & Fairness Docs](https://kubernetes.io/docs/concepts/cluster-administration/flow-control/)
- [CKS Exam Curriculum](https://github.com/cncf/curriculum)
