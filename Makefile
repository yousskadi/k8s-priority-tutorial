# =============================================================
# Makefile — k8s-priority-tutorial
# Permet de tester tous les labs localement SANS CI/CD
#
# Usage :
#   make help          → affiche toutes les commandes
#   make setup         → installe les outils nécessaires
#   make lab01         → lance le lab 01 complet
#   make lab02         → lance le lab 02 complet
#   make lab03         → lance le lab 03 complet
#   make lint          → vérifie les YAML localement
#   make clean         → supprime tous les clusters kind
# =============================================================

CLUSTER_LAB01 := lab01-pod-priority
CLUSTER_LAB02 := lab02-apf
CLUSTER_LAB03 := lab03-production
KIND_IMAGE    := kindest/node:v1.29.0

.DEFAULT_GOAL := help

# ─── Couleurs ────────────────────────────────────────────────
GREEN  := \033[0;32m
YELLOW := \033[1;33m
RED    := \033[0;31m
RESET  := \033[0m
BOLD   := \033[1m

# =============================================================
# HELP
# =============================================================
.PHONY: help
help:
	@echo ""
	@echo "$(BOLD)k8s-priority-tutorial — Commandes disponibles$(RESET)"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@echo "$(YELLOW)Setup$(RESET)"
	@echo "  make check-deps     Vérifie que kind, kubectl, yamllint sont installés"
	@echo "  make lint           Lance yamllint sur tous les manifests"
	@echo ""
	@echo "$(YELLOW)Lab 01 — Pod Priority$(RESET)"
	@echo "  make lab01-cluster  Crée le cluster kind pour le lab 01"
	@echo "  make lab01-setup    Applique les PriorityClasses"
	@echo "  make lab01-fill     Remplit le cluster avec des pods batch"
	@echo "  make lab01-preempt  Déploie un pod critique → observe la préemption"
	@echo "  make lab01-check    Vérifie l'état (pods + events)"
	@echo "  make lab01-clean    Supprime le cluster lab 01"
	@echo "  make lab01          Lance tout le lab 01 d'un coup"
	@echo ""
	@echo "$(YELLOW)Lab 02 — API Priority & Fairness$(RESET)"
	@echo "  make lab02-cluster  Crée le cluster kind pour le lab 02"
	@echo "  make lab02-check    Affiche les FlowSchemas existants"
	@echo "  make lab02-apply    Applique les configs APF custom"
	@echo "  make lab02-test     Lance les pods de test throttling"
	@echo "  make lab02-metrics  Affiche les métriques APF"
	@echo "  make lab02-clean    Supprime le cluster lab 02"
	@echo "  make lab02          Lance tout le lab 02 d'un coup"
	@echo ""
	@echo "$(YELLOW)Lab 03 — Production$(RESET)"
	@echo "  make lab03-cluster  Crée le cluster kind pour le lab 03"
	@echo "  make lab03-apply    Applique toute la config production"
	@echo "  make lab03-status   Affiche l'état complet du cluster"
	@echo "  make lab03-preempt  Simule un incident (préemption batch)"
	@echo "  make lab03-clean    Supprime le cluster lab 03"
	@echo "  make lab03          Lance tout le lab 03 d'un coup"
	@echo ""
	@echo "$(YELLOW)Global$(RESET)"
	@echo "  make clean          Supprime TOUS les clusters kind du tutorial"
	@echo "  make all            Lance les 3 labs en séquence"
	@echo ""

# =============================================================
# VÉRIFICATION DES DÉPENDANCES
# =============================================================
.PHONY: check-deps
check-deps:
	@echo "$(YELLOW)Vérification des dépendances...$(RESET)"
	@command -v kind     >/dev/null 2>&1 || (echo "$(RED)❌ kind manquant$(RESET)    → https://kind.sigs.k8s.io/docs/user/quick-start/#installation" && exit 1)
	@command -v kubectl  >/dev/null 2>&1 || (echo "$(RED)❌ kubectl manquant$(RESET) → https://kubernetes.io/docs/tasks/tools/" && exit 1)
	@echo "$(GREEN)✅ kind    : $$(kind version)$(RESET)"
	@echo "$(GREEN)✅ kubectl : $$(kubectl version --client --short 2>/dev/null || kubectl version --client)$(RESET)"
	@command -v yamllint >/dev/null 2>&1 \
		&& echo "$(GREEN)✅ yamllint : $$(yamllint --version)$(RESET)" \
		|| echo "$(YELLOW)⚠️  yamllint manquant (optionnel) → pip install yamllint$(RESET)"

# =============================================================
# LINT LOCAL
# =============================================================
.PHONY: lint
lint:
	@echo "$(YELLOW)Lint YAML...$(RESET)"
	@command -v yamllint >/dev/null 2>&1 || (echo "$(RED)yamllint non installé : pip install yamllint$(RESET)" && exit 1)
	@find . -name "*.yaml" \
		-not -path "./.git/*" \
		-not -path "./.github/*" \
		-not -name ".yamllint.yaml" \
		| xargs yamllint -c .yamllint.yaml \
		&& echo "$(GREEN)✅ Lint OK$(RESET)"

# =============================================================
# LAB 01 — POD PRIORITY & PREEMPTION
# =============================================================
.PHONY: lab01-cluster
lab01-cluster:
	@echo "$(YELLOW)Création du cluster $(CLUSTER_LAB01)...$(RESET)"
	@kind get clusters 2>/dev/null | grep -q "^$(CLUSTER_LAB01)$$" \
		&& echo "$(YELLOW)Cluster déjà existant, skip$(RESET)" \
		|| kind create cluster --name $(CLUSTER_LAB01) --image $(KIND_IMAGE) --config - <<'EOF'\
		$$(printf 'kind: Cluster\napiVersion: kind.x-k8s.io/v1alpha4\nnodes:\n- role: control-plane\n- role: worker\n- role: worker\n')
	@kubectl config use-context kind-$(CLUSTER_LAB01)
	@kubectl wait --for=condition=Ready nodes --all --timeout=120s
	@echo "$(GREEN)✅ Cluster prêt$(RESET)"

.PHONY: lab01-setup
lab01-setup:
	@echo "$(YELLOW)Application des PriorityClasses...$(RESET)"
	@kubectl config use-context kind-$(CLUSTER_LAB01)
	kubectl apply -f 01-pod-priority/manifests/00-priority-classes.yaml
	@echo ""
	@echo "$(GREEN)PriorityClasses créées :$(RESET)"
	kubectl get priorityclasses
	@echo ""
	@echo "$(BOLD)📌 Points clés :$(RESET)"
	@echo "  • high-priority (1000000)        → peut préempter tout le monde"
	@echo "  • medium-priority (500000)       → peut préempter low"
	@echo "  • low-priority (100000)          → globalDefault, éjecté en premier"
	@echo "  • high-priority-no-preempt (900000) → prioritaire dans la queue mais n'éjecte pas"

.PHONY: lab01-fill
lab01-fill:
	@echo "$(YELLOW)Remplissage du cluster avec des pods batch (low-priority)...$(RESET)"
	@kubectl config use-context kind-$(CLUSTER_LAB01)
	kubectl apply -f 01-pod-priority/manifests/01-low-priority-pods.yaml
	@echo ""
	@echo "$(YELLOW)Attente que les pods démarrent (max 60s)...$(RESET)"
	@sleep 5
	kubectl get pods -o wide
	@echo ""
	@echo "$(BOLD)👀 Observe :$(RESET) certains pods sont peut-être Pending si le cluster est plein"
	@echo "$(BOLD)➡️  Étape suivante :$(RESET) make lab01-preempt"

.PHONY: lab01-preempt
lab01-preempt:
	@echo "$(YELLOW)Déploiement du pod critique (high-priority)...$(RESET)"
	@kubectl config use-context kind-$(CLUSTER_LAB01)
	kubectl apply -f 01-pod-priority/manifests/02-high-priority-pod.yaml
	@echo ""
	@echo "$(BOLD)👀 Observe la préemption en temps réel :$(RESET)"
	@echo "  Des pods batch-job-filler vont passer en Terminating"
	@echo "  payment-api-critical va passer en Running"
	@echo ""
	@echo "$(YELLOW)Surveillance pendant 30s...$(RESET)"
	@for i in $$(seq 1 6); do \
		echo "--- $$i/6 ---"; \
		kubectl get pods --sort-by='.status.phase' 2>/dev/null; \
		sleep 5; \
	done

.PHONY: lab01-check
lab01-check:
	@echo "$(YELLOW)=== État du cluster lab01 ===$(RESET)"
	@kubectl config use-context kind-$(CLUSTER_LAB01)
	@echo ""
	@echo "$(BOLD)Pods et leur priorité :$(RESET)"
	kubectl get pods -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,PRIORITY-CLASS:.spec.priorityClassName,PRIORITY:.spec.priority,NODE:.spec.nodeName'
	@echo ""
	@echo "$(BOLD)Events de préemption :$(RESET)"
	kubectl get events --sort-by='.lastTimestamp' | grep -iE 'preempt|evict' || echo "  (aucun event de préemption pour l'instant)"
	@echo ""
	@echo "$(BOLD)Ressources des noeuds :$(RESET)"
	kubectl describe nodes | grep -A5 "Allocated resources" | grep -v "^--$$"

.PHONY: lab01-clean
lab01-clean:
	@echo "$(YELLOW)Suppression du cluster $(CLUSTER_LAB01)...$(RESET)"
	kind delete cluster --name $(CLUSTER_LAB01) 2>/dev/null || true
	@echo "$(GREEN)✅ Cluster supprimé$(RESET)"

.PHONY: lab01
lab01: check-deps lab01-clean
	@echo "$(BOLD)════════════════════════════════════════$(RESET)"
	@echo "$(BOLD)  LAB 01 — Pod Priority & Preemption$(RESET)"
	@echo "$(BOLD)════════════════════════════════════════$(RESET)"
	@$(MAKE) _lab01-create-cluster
	@$(MAKE) lab01-setup
	@echo ""
	@echo "$(YELLOW)Remplissage du cluster...$(RESET)"
	kubectl apply -f 01-pod-priority/manifests/01-low-priority-pods.yaml
	@echo "$(YELLOW)Attente 15s pour que les pods démarrent...$(RESET)"
	@sleep 15
	@echo ""
	@echo "$(BOLD)État avant préemption :$(RESET)"
	kubectl get pods
	@echo ""
	@echo "$(YELLOW)Déploiement du pod critique...$(RESET)"
	kubectl apply -f 01-pod-priority/manifests/02-high-priority-pod.yaml
	@echo "$(YELLOW)Surveillance pendant 45s...$(RESET)"
	@for i in $$(seq 1 9); do \
		echo ""; \
		echo "--- Tick $$i/9 (5s) ---"; \
		kubectl get pods --sort-by='.status.phase'; \
	done
	@echo ""
	@echo "$(BOLD)Events de préemption :$(RESET)"
	kubectl get events --sort-by='.lastTimestamp' | grep -iE 'preempt|evict' || echo "  (augmente les replicas si aucune préemption)"
	@echo ""
	@echo "$(GREEN)✅ Lab 01 terminé$(RESET)"

# Helper interne
.PHONY: _lab01-create-cluster
_lab01-create-cluster:
	@cat <<'EOF' | kind create cluster --name $(CLUSTER_LAB01) --image $(KIND_IMAGE) --config -
	kind: Cluster
	apiVersion: kind.x-k8s.io/v1alpha4
	nodes:
	- role: control-plane
	- role: worker
	- role: worker
	EOF
	kubectl config use-context kind-$(CLUSTER_LAB01)
	kubectl wait --for=condition=Ready nodes --all --timeout=120s

# =============================================================
# LAB 02 — API PRIORITY & FAIRNESS
# =============================================================
.PHONY: lab02-cluster
lab02-cluster:
	@echo "$(YELLOW)Création du cluster $(CLUSTER_LAB02)...$(RESET)"
	@cat <<'EOF' | kind create cluster --name $(CLUSTER_LAB02) --image $(KIND_IMAGE) --config -
	kind: Cluster
	apiVersion: kind.x-k8s.io/v1alpha4
	nodes:
	- role: control-plane
	- role: worker
	EOF
	@kubectl config use-context kind-$(CLUSTER_LAB02)
	@kubectl wait --for=condition=Ready nodes --all --timeout=120s
	@echo "$(GREEN)✅ Cluster prêt$(RESET)"

.PHONY: lab02-check
lab02-check:
	@echo "$(YELLOW)=== FlowSchemas existants (triés par precedence) ===$(RESET)"
	@kubectl config use-context kind-$(CLUSTER_LAB02)
	kubectl get flowschemas --sort-by='.spec.matchingPrecedence' \
		-o custom-columns='NAME:.metadata.name,PRIORITY-LEVEL:.spec.priorityLevelConfiguration.name,PRECEDENCE:.spec.matchingPrecedence'
	@echo ""
	@echo "$(YELLOW)=== PriorityLevelConfigurations ===$(RESET)"
	kubectl get prioritylevelconfigurations
	@echo ""
	@echo "$(BOLD)📌 Points clés :$(RESET)"
	@echo "  • matchingPrecedence plus petit = matché EN PREMIER"
	@echo "  • exempt = jamais throttlé (scheduler, controller-manager)"
	@echo "  • catch-all (10000) = filet de sécurité pour tout le reste"

.PHONY: lab02-apply
lab02-apply:
	@echo "$(YELLOW)Application des configs APF custom...$(RESET)"
	@kubectl config use-context kind-$(CLUSTER_LAB02)
	@echo "Étape 1/2 : PriorityLevels (doit être avant les FlowSchemas)"
	kubectl apply -f 02-api-priority-fairness/manifests/02-priority-level-custom.yaml
	@echo ""
	@echo "Étape 2/2 : FlowSchemas"
	kubectl apply -f 02-api-priority-fairness/manifests/01-flow-schema-custom.yaml
	@echo ""
	@echo "$(GREEN)=== Résultat ===$(RESET)"
	kubectl get flowschemas --sort-by='.spec.matchingPrecedence' | grep -E "NAME|demo-"
	kubectl get prioritylevelconfigurations | grep -E "NAME|demo-"
	@echo ""
	@echo "$(BOLD)📌 Note :$(RESET) demo-restricted-sa (4999) est matché AVANT demo-workloads (5000)"
	@echo "  → le SA 'restricted-sa' du namespace demo est isolé dans sa propre file"

.PHONY: lab02-test
lab02-test:
	@echo "$(YELLOW)Déploiement des pods de test throttling...$(RESET)"
	@kubectl config use-context kind-$(CLUSTER_LAB02)
	kubectl apply -f 02-api-priority-fairness/manifests/03-test-throttling.yaml
	@echo ""
	@echo "$(YELLOW)Attente 10s que les pods démarrent...$(RESET)"
	@sleep 10
	kubectl get pods -n demo
	@echo ""
	@echo "$(BOLD)Pour observer les logs en direct :$(RESET)"
	@echo "  kubectl logs -n demo -f api-load-generator-normal"
	@echo "  kubectl logs -n demo -f api-load-generator-restricted"

.PHONY: lab02-metrics
lab02-metrics:
	@echo "$(YELLOW)=== Métriques APF ===$(RESET)"
	@kubectl config use-context kind-$(CLUSTER_LAB02)
	@echo "$(BOLD)Requêtes en cours d'exécution par niveau :$(RESET)"
	kubectl get --raw /metrics 2>/dev/null | grep 'apiserver_flowcontrol_current_executing_seats' | grep -v '#' || echo "  (métriques non disponibles sur ce cluster)"
	@echo ""
	@echo "$(BOLD)Requêtes rejetées (429) par niveau :$(RESET)"
	kubectl get --raw /metrics 2>/dev/null | grep 'apiserver_flowcontrol_rejected_requests_total' | grep -v '#' || echo "  (aucun rejet pour l'instant)"

.PHONY: lab02-clean
lab02-clean:
	@echo "$(YELLOW)Suppression du cluster $(CLUSTER_LAB02)...$(RESET)"
	kind delete cluster --name $(CLUSTER_LAB02) 2>/dev/null || true
	@echo "$(GREEN)✅ Cluster supprimé$(RESET)"

.PHONY: lab02
lab02: check-deps lab02-clean
	@echo "$(BOLD)════════════════════════════════════════$(RESET)"
	@echo "$(BOLD)  LAB 02 — API Priority & Fairness$(RESET)"
	@echo "$(BOLD)════════════════════════════════════════$(RESET)"
	@$(MAKE) lab02-cluster
	@$(MAKE) lab02-check
	@$(MAKE) lab02-apply
	@$(MAKE) lab02-test
	@echo "$(GREEN)✅ Lab 02 terminé$(RESET)"
	@echo ""
	@echo "$(BOLD)Commandes pour explorer :$(RESET)"
	@echo "  make lab02-metrics"
	@echo "  kubectl logs -n demo -f api-load-generator-normal"

# =============================================================
# LAB 03 — PRODUCTION
# =============================================================
.PHONY: lab03-cluster
lab03-cluster:
	@echo "$(YELLOW)Création du cluster $(CLUSTER_LAB03) (3 workers)...$(RESET)"
	@cat <<'EOF' | kind create cluster --name $(CLUSTER_LAB03) --image $(KIND_IMAGE) --config -
	kind: Cluster
	apiVersion: kind.x-k8s.io/v1alpha4
	nodes:
	- role: control-plane
	- role: worker
	- role: worker
	- role: worker
	EOF
	@kubectl config use-context kind-$(CLUSTER_LAB03)
	@kubectl wait --for=condition=Ready nodes --all --timeout=180s
	@echo "$(GREEN)✅ Cluster prêt$(RESET)"

.PHONY: lab03-apply
lab03-apply:
	@echo "$(YELLOW)Application de la config production (ordre des dépendances)...$(RESET)"
	@kubectl config use-context kind-$(CLUSTER_LAB03)
	@echo "1/6 Namespaces + ResourceQuotas"
	kubectl apply -f 03-production-like/manifests/00-namespaces.yaml
	@echo "2/6 PriorityClasses"
	kubectl apply -f 03-production-like/manifests/01-priority-classes.yaml
	@echo "3/6 APF PriorityLevels (avant les FlowSchemas)"
	kubectl apply -f 03-production-like/manifests/06-apf-priority-levels.yaml
	@echo "4/6 APF FlowSchemas"
	kubectl apply -f 03-production-like/manifests/05-apf-flow-schemas.yaml
	@echo "5/6 Workloads critiques (production)"
	kubectl apply -f 03-production-like/manifests/02-critical-workloads.yaml
	@echo "6/6 Workloads standard + batch"
	kubectl apply -f 03-production-like/manifests/03-standard-workloads.yaml
	kubectl apply -f 03-production-like/manifests/04-batch-workloads.yaml
	@echo ""
	@echo "$(YELLOW)Attente du rollout production...$(RESET)"
	kubectl rollout status deployment/payment-api -n production --timeout=120s
	kubectl rollout status deployment/auth-service -n production --timeout=120s
	@echo "$(GREEN)✅ Config production appliquée$(RESET)"

.PHONY: lab03-status
lab03-status:
	@kubectl config use-context kind-$(CLUSTER_LAB03)
	@echo "$(BOLD)=== PriorityClasses ===$(RESET)"
	kubectl get priorityclasses --no-headers | grep -v "^system-"
	@echo ""
	@echo "$(BOLD)=== Pods par namespace et priorité ===$(RESET)"
	kubectl get pods -A \
		-o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,PRIORITY-CLASS:.spec.priorityClassName,STATUS:.status.phase' \
		| grep -v "^kube-"
	@echo ""
	@echo "$(BOLD)=== PodDisruptionBudgets ===$(RESET)"
	kubectl get pdb -n production
	@echo ""
	@echo "$(BOLD)=== FlowSchemas custom ===$(RESET)"
	kubectl get flowschemas | grep -E "production-|staging-|batch-"

.PHONY: lab03-preempt
lab03-preempt:
	@echo "$(BOLD)════════════════════════════════════════$(RESET)"
	@echo "$(BOLD)  SCÉNARIO : Incident production$(RESET)"
	@echo "$(BOLD)════════════════════════════════════════$(RESET)"
	@kubectl config use-context kind-$(CLUSTER_LAB03)
	@echo ""
	@echo "$(YELLOW)Étape 1 : Saturation du cluster avec des batch jobs...$(RESET)"
	kubectl scale deployment data-pipeline -n batch --replicas=15
	@sleep 10
	kubectl get pods -n batch | head -20
	@echo ""
	@echo "$(YELLOW)Étape 2 : Déploiement d'un pod d'urgence (critical)...$(RESET)"
	kubectl run incident-response \
		--image=nginx:alpine \
		--namespace=production \
		--overrides='{"spec":{"priorityClassName":"critical","containers":[{"name":"incident-response","image":"nginx:alpine","resources":{"requests":{"memory":"128Mi","cpu":"100m"}}}]}}'
	@echo ""
	@echo "$(YELLOW)Observation pendant 30s...$(RESET)"
	@for i in $$(seq 1 6); do \
		echo "--- $$i/6 ---"; \
		kubectl get pod incident-response -n production 2>/dev/null; \
		kubectl get events -n batch --sort-by='.lastTimestamp' 2>/dev/null | grep -i evict | tail -3; \
		sleep 5; \
	done
	@echo ""
	@echo "$(BOLD)Events de préemption :$(RESET)"
	kubectl get events -A --sort-by='.lastTimestamp' | grep -iE 'preempt|evict' | tail -10

.PHONY: lab03-clean
lab03-clean:
	@echo "$(YELLOW)Suppression du cluster $(CLUSTER_LAB03)...$(RESET)"
	kind delete cluster --name $(CLUSTER_LAB03) 2>/dev/null || true
	@echo "$(GREEN)✅ Cluster supprimé$(RESET)"

.PHONY: lab03
lab03: check-deps lab03-clean
	@echo "$(BOLD)════════════════════════════════════════$(RESET)"
	@echo "$(BOLD)  LAB 03 — Scénario Production$(RESET)"
	@echo "$(BOLD)════════════════════════════════════════$(RESET)"
	@$(MAKE) lab03-cluster
	@$(MAKE) lab03-apply
	@$(MAKE) lab03-status
	@echo ""
	@echo "$(GREEN)✅ Lab 03 prêt$(RESET)"
	@echo ""
	@echo "$(BOLD)Prochaines étapes :$(RESET)"
	@echo "  make lab03-preempt  → simule un incident"
	@echo "  make lab03-status   → affiche l'état complet"

# =============================================================
# GLOBAL
# =============================================================
.PHONY: clean
clean:
	@echo "$(YELLOW)Suppression de tous les clusters du tutorial...$(RESET)"
	kind delete cluster --name $(CLUSTER_LAB01) 2>/dev/null || true
	kind delete cluster --name $(CLUSTER_LAB02) 2>/dev/null || true
	kind delete cluster --name $(CLUSTER_LAB03) 2>/dev/null || true
	@echo "$(GREEN)✅ Tous les clusters supprimés$(RESET)"

.PHONY: all
all: lab01-clean lab02-clean lab03-clean
	@echo "$(BOLD)Lancement des 3 labs en séquence...$(RESET)"
	@$(MAKE) lab01
	@$(MAKE) lab01-clean
	@$(MAKE) lab02
	@$(MAKE) lab02-clean
	@$(MAKE) lab03
	@echo "$(GREEN)✅ Tous les labs terminés$(RESET)"
