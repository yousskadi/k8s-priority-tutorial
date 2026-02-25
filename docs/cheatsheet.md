# 📋 Cheatsheet CKS — Priority & Fairness

## Pod Priority Quick Reference

```bash
# Voir toutes les PriorityClasses
kubectl get priorityclasses

# Voir la priorité d'un pod
kubectl get pod <pod> -o jsonpath='{.spec.priority}'
kubectl get pod <pod> -o jsonpath='{.spec.priorityClassName}'

# Tous les pods avec leur priorité
kubectl get pods -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PRIORITY-CLASS:.spec.priorityClassName,PRIORITY:.spec.priority'

# Events de préemption
kubectl get events -A | grep -i preempt

# Décrire une PriorityClass
kubectl describe priorityclass <name>
```

## API Priority & Fairness Quick Reference

```bash
# FlowSchemas triées par ordre de matching
kubectl get flowschemas --sort-by='.spec.matchingPrecedence'

# PriorityLevelConfigurations
kubectl get prioritylevelconfigurations

# Métriques APF (requêtes rejetées)
kubectl get --raw /metrics | grep apiserver_flowcontrol_rejected

# Métriques APF (en cours)
kubectl get --raw /metrics | grep apiserver_flowcontrol_current_executing

# Voir quelle FlowSchema a matché une requête (dans les logs apiserver)
kubectl logs -n kube-system -l component=kube-apiserver | grep flowcontrol

# Condition d'une FlowSchema (Stale = référence un PriorityLevel qui n'existe pas)
kubectl get flowschemas -o wide
```

## Objets importants à connaître pour le CKS

### PriorityClass
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass           # cluster-scoped
metadata:
  name: my-priority
value: 1000000                # entier, plus grand = plus prioritaire
globalDefault: false          # un seul peut être true
preemptionPolicy: PreemptLowerPriority  # ou Never
description: "..."
```

### FlowSchema
```yaml
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: FlowSchema              # cluster-scoped
metadata:
  name: my-schema
spec:
  priorityLevelConfiguration:
    name: my-level            # référence un PriorityLevelConfiguration
  matchingPrecedence: 1000    # plus petit = matché en premier
  distinguisherMethod:
    type: ByNamespace         # ou ByUser
  rules:
  - subjects:
    - kind: ServiceAccount    # ou User, Group
      serviceAccount:
        namespace: my-ns
        name: my-sa
    resourceRules:
    - verbs: ["*"]
      apiGroups: ["*"]
      resources: ["*"]
```

### PriorityLevelConfiguration
```yaml
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: PriorityLevelConfiguration  # cluster-scoped
metadata:
  name: my-level
spec:
  type: Limited                # ou Exempt
  limited:
    nominalConcurrencyShares: 30
    limitResponse:
      type: Queue              # ou Reject
      queuing:
        queues: 16
        handSize: 4
        queueLengthLimit: 50
```

## Pièges fréquents au CKS

| Piège | Réalité |
|-------|---------|
| PriorityClass dans un namespace | ❌ C'est cluster-scoped |
| FlowSchema dans un namespace | ❌ C'est cluster-scoped |
| `matchingPrecedence` élevé = matché en premier | ❌ Plus petit = matché en premier |
| `exempt` type → throttlé fortement | ❌ `exempt` = jamais throttlé |
| Modifier les FlowSchemas système | ⚠️ Risque de casser le cluster |
| `preemptionPolicy: Never` empêche le scheduling | ❌ Schedulé mais sans préempter |

## Commandes de diagnostic

```bash
# Pod en Pending à cause de resources insuffisantes
kubectl describe pod <pod> | grep -A10 Events

# Vérifier si la préemption a eu lieu
kubectl get events --sort-by='.lastTimestamp' | grep -iE 'preempt|evict'

# Vérifier les FlowSchemas en erreur (Stale)
kubectl get flowschemas -o json | jq '.items[] | select(.status.conditions[].type == "Dangling") | .metadata.name'

# APF : voir le nombre de seats par niveau
kubectl get --raw /metrics | grep apiserver_flowcontrol_nominal_seats
```
