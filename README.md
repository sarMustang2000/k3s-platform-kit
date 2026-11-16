# k3s-platform-kit

Everything I use to take empty Ubuntu servers to a production platform that a
small team can run: hardened hosts, a single-node k3s cluster, MySQL, a TLS
edge, nightly backups, metrics, logs and alerting, one Helm chart for every
service, and a CI pipeline that won't ship a leaked secret, a known-vulnerable
dependency or an unsigned image.

It is distilled from infrastructure I have built and operated, with everything
environment-specific taken out. The comments are the useful part: most of them
record something that broke and why the code now looks the way it does.

```
                         ┌──────────────── CI (GitHub Actions / GitLab CI) ────────────────┐
  git push ─▶ build ─▶ gitleaks · semgrep · trivy (deps, IaC, image) · SBOM ─▶ cosign sign ─▶ helm upgrade --atomic
                         └─────────────────────────────────────────────────────────┬───────┘
                                                        namespace-scoped deployer │
  Users ─▶ edge nginx (Let's Encrypt, HSTS, login rate limit) ─▶ NodePort ─▶ k3s ─┴─▶ apps (helm/app)
                                                                              │
                                    MySQL (per-app users, firewalled) ◀───────┤
                                    VictoriaMetrics · VictoriaLogs · Grafana ◀┤─▶ Alertmanager ─▶ Telegram
                                    nightly mysqldump + uploads ─▶ rsync off-site
```

## What's here

| Path | What it is |
|---|---|
| [`ansible/`](ansible) | Roles for host baseline, k3s, MySQL, TLS edge, backups, monitoring; one `site.yml` |
| [`helm/app`](helm/app) | One chart for web apps, workers and cron jobs, with secure defaults |
| [`.github/workflows/security.yml`](.github/workflows/security.yml) | Reusable security gate other repositories call |
| [`ci/github/deploy.example.yml`](ci/github/deploy.example.yml) | Build → scan → sign → deploy for a service repo |
| [`ci/gitlab/security.gitlab-ci.yml`](ci/gitlab/security.gitlab-ci.yml) | The same gate and deploy template for GitLab CI |
| [`k8s/`](k8s) | Least-privilege CI deployer (RBAC) and its kubeconfig generator |
| [`observability/`](observability) | Local OpenTelemetry stack: Collector, Jaeger, Prometheus, Loki, Grafana |

## Quick start

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml -p .collections
cp inventory/hosts.example.yml inventory/hosts.yml                    # your servers, by role
cp inventory/group_vars/all/vault.example.yml inventory/group_vars/all/vault.yml
$EDITOR inventory/group_vars/all/main.yml                             # domain, admin CIDRs, sites
ansible-vault encrypt inventory/group_vars/all/vault.yml
ansible-playbook playbooks/site.yml --ask-vault-pass
```

One VM can hold every role. Then deploy a service with the chart:

```bash
helm upgrade --install api helm/app -f my-values.yaml --set image.tag=$GIT_SHA --atomic
```

And try the observability stack locally (no cluster needed):

```bash
docker compose -f observability/docker-compose.yml --profile demo up    # Grafana on :3000
```

## Design notes

**Host baseline (`common`).** Unattended security upgrades, UFW default-deny,
fail2ban, key-only SSH, container-friendly sysctls. The SSH drop-in is named
`01-…`, not `90-…`: sshd keeps the *first* value it reads, and cloud-init's
`50-cloud-init.conf` turns password login back on. Getting that wrong makes
hardening a silent no-op.

**k3s.** Single node, Traefik disabled (nginx is the entry point). The
Kubernetes API is open only to admin networks and CI runners, and the role
explicitly *deletes* any old world-open rule, because UFW only ever adds.
Existing clusters are never upgraded by accident. Upgrades are opt-in and
asserted to move one minor version at a time, which is all k3s supports.

**MySQL.** One database and user per app and environment, granted only to
the k3s node's address (and the pod CIDR when both share a host). The config
file is named `zz-…` because MySQL reads includes alphabetically and the last
`bind-address` wins. A `90-…` file loses to Ubuntu's `mysqld.cnf` and leaves
the server on loopback.

**TLS edge.** nginx owns its configuration entirely, and certbot only *issues*
certificates (`certonly --webroot`). Letting `certbot --nginx` edit templated
files meant every Ansible run dropped HTTPS. Vhosts are written in two passes:
HTTP-only until a certificate exists, so a name that doesn't resolve yet
degrades to HTTP instead of breaking nginx. Login POSTs are rate-limited per
IP, and security headers are only added where the app didn't set its own.

**Backups.** Nightly `mysqldump --single-transaction` (a consistent snapshot
without locking) plus upload directories, local retention, optional rsync
off-site. Restore commands are at the top of the script.

**Monitoring.** `victoria-metrics-k8s-stack`: VictoriaMetrics, VictoriaLogs,
vmalert, Alertmanager and Grafana, chosen over Prometheus because disk was the
binding constraint. k3s's embedded control-plane components are not scraped
(they listen on loopback inside the k3s process), which would otherwise mean
"target down" alerts forever. Retention is capped by size as well as time.
Alerts go to Telegram, and the values file holding the bot token is written
0600 and deleted after deploy.

**Helm chart.** One chart for every service: non-root, read-only root
filesystem, all capabilities dropped, seccomp, no service-account token, a
NetworkPolicy, and no CPU limit (throttling costs more latency than it saves).
`image.tag` is required, so nothing deploys as `latest`. Migrations run as a
pre-upgrade hook that blocks the rollout if it fails, and their ConfigMap is a
lower-weight hook so it exists on first install too. PVCs survive `helm
uninstall`.

**CI security gate.** gitleaks over full history (a secret deleted later is
still leaked), semgrep, trivy for dependencies, IaC and the built image (only
failing on findings an upgrade can fix), a CycloneDX SBOM, and keyless cosign
signing of the image *digest*. Deploys use a namespace-scoped service account,
not cluster-admin, and `helm --atomic` rolls back by itself.

## Checked in CI

`ansible-lint` (production profile) and syntax check, `helm lint --strict` and
kubeconform on rendered manifests, `docker compose config` for the
observability stack.
