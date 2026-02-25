#!/bin/bash
# =============================================================
# setup-repo.sh
# Initialise le repo git avec les branches recommandées
# =============================================================

set -e

echo "=== Setup du repo k8s-priority-tutorial ==="

# Init git
git init
git add .
git commit -m "feat: initial commit — k8s priority tutorial

Contenu:
- Module 01: Pod Priority & Preemption
- Module 02: API Priority & Fairness
- Module 03: Scénario Production
- CI/CD: GitHub Actions (validate + e2e)"

# Branches
echo ""
echo "=== Création des branches ==="

# develop — branche d'intégration
git checkout -b develop
git checkout main 2>/dev/null || git checkout -b main

# Branche pour chaque module
git checkout -b feature/01-pod-priority
git checkout main 2>/dev/null || git checkout develop
git merge feature/01-pod-priority --no-ff -m "merge: module 01 pod priority"

git checkout -b feature/02-apf
git checkout main 2>/dev/null || git checkout develop
git merge feature/02-apf --no-ff -m "merge: module 02 API priority & fairness"

git checkout -b feature/03-production
git checkout main 2>/dev/null || git checkout develop
git merge feature/03-production --no-ff -m "merge: module 03 production scenario"

echo ""
echo "=== Branches créées ==="
git branch -a

echo ""
echo "=== Pour publier sur GitHub ==="
echo ""
echo "gh repo create k8s-priority-tutorial --public --description 'Kubernetes Pod Priority & API Priority Fairness — Tutorial CKS'"
echo "git remote add origin https://github.com/yousskadi/k8s-priority-tutorial.git"
echo "git push -u origin main"
echo "git push origin develop"
echo ""
echo "=== Protéger la branche main (optionnel) ==="
echo "gh api repos/VOTRE_USER/k8s-priority-tutorial/branches/main/protection \\"
echo "  --method PUT \\"
echo "  --field required_pull_request_reviews.required_approving_review_count=1 \\"
echo "  --field enforce_admins=false"
