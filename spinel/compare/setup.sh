#!/bin/bash
# Builds the fixture commands.sh runs k in: a HOME whose ~/.k has two contexts, each a gitops repository with
# release history and generator templates, plus bare repositories to push to under <dir>-remotes.
#
# Usage: spinel/compare/setup.sh <dir>
set -e
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
T=$1; rm -rf "$T" "$T-remotes"; mkdir -p "$T/.k" "$T-remotes/acme"
cat > "$T/.k/config" <<YAML
---
context: demo
contexts:
  demo:
    github_organization: acme
    repository: git@github.com:acme/demo.git
    registry: ghcr.io
    registry_namespace: acme
    kubectl_context: none
  other:
    github_organization: acme
    repository: git@github.com:acme/other.git
    registry: ghcr.io
    registry_namespace: acme
    kubectl_context: none-2
YAML
export GIT_AUTHOR_NAME="Ada Admin" GIT_AUTHOR_EMAIL=ada@example.com GIT_COMMITTER_NAME="Ada Admin" GIT_COMMITTER_EMAIL=ada@example.com
for repo in demo other; do
  d="$T/.k/$repo"; mkdir -p "$d"; cd "$d"; git init -q -b main
  for app in web-app worker; do
    mkdir -p applications/$app/templates
    printf 'apiVersion: v2\nname: %s\nversion: 0.1.0\n' $app > applications/$app/Chart.yaml
    if [ $app = web-app ]; then env_from=$'\n- secretRef:\n    name: app-env'; else env_from=" []"; fi
    cat > applications/$app/values.yaml <<YAML
image: ghcr.io/acme/$app:v1
envFrom:$env_from
env: []
deployments:
  web:
    replicas: 2
YAML
  done
  mkdir -p generators/deployments generators/resources applications/shared-secrets
  cat > generators/deployments/worker.yaml <<'YAML'
# Example values.yaml:
# deployments:
#   %{camelName}:
#     replicas: 1
# env:
#   QUEUE: default

apiVersion: apps/v1
kind: Deployment
metadata:
  name: %{application}-%{name}
YAML
  printf '# Example values.yaml:\n# env:\n#   CONFIG_NAME: %%{name}\n\napiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: %%{application}-%%{name}\n' > generators/resources/configmap.yaml
  printf 'apiVersion: bitnami.com/v1alpha1\nkind: SealedSecret\n' > applications/shared-secrets/app-env.yaml
  git add -A; GIT_AUTHOR_DATE="2026-09-01T10:00:00+0200" GIT_COMMITTER_DATE="2026-09-01T10:00:00+0200" git commit -q -m init
  for i in 2 3 4; do
    perl -pi -e "s/:v$((i-1))/:v$i/" applications/web-app/values.yaml
    git add -A; GIT_AUTHOR_DATE="2026-09-0${i}T1${i}:00:00+0200" GIT_COMMITTER_DATE="2026-09-0${i}T1${i}:00:00+0200" git commit -q -m "web-app: deploy v$i" -m "Release notes for v$i"
  done
  git clone -q --bare . "$T-remotes/acme/$repo.git"
  # commands.sh points git@github.com: at the remotes directory through url.insteadOf
  git remote add origin "git@github.com:acme/$repo.git"
  git -c url."$T-remotes/".insteadOf=git@github.com: fetch -q origin; git branch -q --set-upstream-to=origin/main
done
git clone -q --bare "$T/.k/other" "$T-remotes/acme/third.git"
