# OSS MLOps Platform Upgrade Feasibility Report

> Author: Zhen Qi
> Date: April 2026
> Version: v11 (small polish: filled in K8s row Source column in §2.1 table, deduplicated §8.1 item 2 against §2.1 and Phase 1)
> Audience: Jukka Remes (summer upgrade implementer) / Future student teams (reference)

---

## 1. Purpose of This Document

The OSS MLOps Platform was built in 2022-2023, and its core components have not been upgraded since. The stack is outdated, and upgrading to current LTS versions will improve maintainability, community support, and onboarding experience.

The good news is that the platform's services (Kubeflow, MLflow, MinIO, PostgreSQL, Prometheus, Grafana, etc.) **run independently in separate namespaces and do not depend on each other at the service level**. This means each service can be upgraded to its own best LTS version without requiring all services to move in lockstep.

The only area where version differences could cause issues is at the **pipeline code level**: if the Python dependencies required by different service versions become incompatible within the same pipeline. But this is a pipeline code concern, not a platform service concern, and is treated as separate follow-up work (see Appendix C).

This report provides a practical plan for updating the platform's code and configuration files so that fresh installs use newer LTS versions. It covers:

1. **Current versions** of all platform services
2. **Target LTS versions** for each service
3. **A service-by-service update plan** with effort estimates
4. **Verification procedures** to confirm fresh installs work correctly

### Scope Boundaries (Confirmed by Jukka)

- **This is a clean install upgrade**: we update code and config files in the repo so that fresh installs use newer versions of services. We are not doing in-place upgrades on existing clusters.
- **Each service is upgraded independently** to its own best LTS version
- **No data migration needed**: fresh installs start clean
- **Preserve existing deployment options**: users still deploy via `setup.sh` with options 1-6, on cPouta, Verda, or their own machines
- **Pipeline code migration is separate work**: not part of this upgrade
- **Runner setup is out of scope**: no in-cluster runner exists yet; Tran Anh and Roope are investigating this separately

---

## 2. Current vs Target Versions

### 2.1 Version Overview

Services in this platform fall into two groups based on **how they get upgraded**, which directly affects how implementation work is scoped:

- **Kubeflow Bundle** — Nine components packaged together by the Kubeflow distribution. Updating the Kubeflow manifests directory in Phase 2 upgrades all of them in a single action. They are listed individually below for transparency, but they do **not** represent independent upgrade work — the entire bundle moves together.
- **Independent Services** — Components deployed separately by this repo (MLflow, MinIO, PostgreSQL, monitoring stack, base Kubernetes). Each is upgraded in its own phase with its own configuration files.

Target versions are selected based on LTS principles: stable, supported for the long term, not necessarily the latest release.

#### Kubeflow Bundle (one upgrade action via Kubeflow 1.9.1 manifests, Phase 2)

| Component | Current Version | Target Version |
|-----------|----------------|----------------|
| **Kubeflow** (bundle anchor) | 1.8.0-rc.0 | **1.9.1** |
| KFP Backend | 2.0.1 | bundled (uses Argo Workflows 3.4) |
| KServe | 0.11.0 | **0.13** |
| Istio | 1.17.3 | **1.22** |
| Knative Serving | 1.10.2 | **1.12** |
| Knative Eventing | 1.10.1 | **1.12** |
| Cert Manager | 1.12.2 | **1.14** |
| Katib | 0.16.0-rc.1 | bundled |
| Authentication | OIDC AuthService | **oauth2-proxy 7.6.0** + Dex 2.39 as IdP |

All current versions taken from the Kubeflow manifests README version matrix. **The entire bundle upgrades as one unit in Phase 2** — there is no independent "upgrade KServe" or "upgrade Istio" phase.

#### Independent Services (each upgraded in its own phase)

| Service | Current Version | Source | Target Version | Phase |
|---------|----------------|--------|---------------|-------|
| MLflow server | 2.4.0 | `docker/Dockerfile` | **3.8.1** | Phase 3 |
| Python (server) | 3.8.3 | `docker/Dockerfile` | **3.10** | Phase 3 |
| Python (pipeline) | 3.9 / 3.10 | `demo-pipeline.ipynb` | **3.10** | Phase 3 |
| boto3 (server) | 1.15.16 | `docker/Dockerfile` | latest compatible | Phase 3 |
| MinIO | RELEASE.2023-02-10T18-48-39Z | `deployment/mlflow/minio/` | latest stable | Phase 4 |
| PostgreSQL | 13 (**EOL**) | `deployment/mlflow/postgres/` | **16.x** | Phase 4 |
| Prometheus | v2.33.4 | `deployment/monitoring/prometheus/` | latest LTS | Phase 5 |
| Grafana | 8.4.3 | `deployment/monitoring/grafana/` | **11.x LTS** | Phase 5 |
| Kubernetes (KIND on cPouta, k3s on Verda) | To be confirmed on-cluster | cPouta cluster / Verda VM (run-time check) | **1.29 - 1.30** | Phase 1 |

**Note on Kubernetes target [Multi-cloud constraint]**: Capped at 1.30 because Liqo 1.0.1 (used by the multi-cloud setup) only supports K8s 1.29-1.30. Targeting 1.31 would require upgrading Liqo to 1.1.x first. Single-cloud deployments are not bound by this cap and could go higher, but staying at 1.29-1.30 is recommended for consistency. See Phase 1 and Phase 6.

**Note on KFP versions**: Backend is 2.0.1 but pipeline SDK is 1.8.14. The backend is already v2, but pipeline code still uses the v1 SDK in V2_COMPATIBLE mode. This does not affect the platform upgrade (pipeline code migration is separate work, see Appendix C).

### 2.2 What "Bundled with Kubeflow 1.9.1" Means in Practice

When the implementer updates the Kubeflow manifests directory in Phase 2, **all nine bundle components above are replaced in the same action**, because they all live inside that directory. There is no need to separately download or install KServe 0.13, Istio 1.22, Knative 1.12, Cert Manager 1.14, oauth2-proxy 7.6.0, etc. — they ship inside the Kubeflow 1.9.1 manifests package.

This is not coupling at the runtime level (services still run in separate pods and don't share dependencies). It is **packaging at the distribution level** — analogous to how installing a Linux distribution gives you a curated set of pre-integrated packages without you choosing each one individually.

The practical implication: when reading Phase 2's effort estimate (5-8 days), understand that this single phase covers the upgrade of all nine bundle components, not just "Kubeflow itself."

### 2.3 The One Real Constraint: Python Dependencies at Pipeline Level

The only scenario where version differences could cause problems is if service versions become so different that their Python dependencies conflict at the pipeline level. However, this is a **pipeline code concern**, not a platform service concern. Services run in separate pods and do not share Python environments. See Appendix C.

---

## 3. Repository Structure Overview

### 3.1 Base Configuration Directories

```
deployment/
├── kubeflow/          # Kubeflow base manifests (currently 1.8.0-rc.0)
│   └── manifests/     # Fork/clone of upstream kubeflow/manifests
│       ├── apps/      # Official Kubeflow components (KFP, Katib, Notebooks, etc.)
│       ├── common/    # Shared services (Istio 1.17, cert-manager, Dex, Knative, etc.)
│       └── contrib/   # Third-party (KServe)
├── mlflow/            # MLflow deployment configuration
│   ├── base/          # MLflow deployment, service, namespace
│   ├── postgres/      # PostgreSQL 13 deployment (backend store)
│   ├── minio/         # MinIO 2023-02 deployment (artifact store)
│   └── envs/          # Environment overlays (local postgres, GCP CloudSQL, postgres+minio)
├── monitoring/        # Monitoring stack
│   ├── prometheus/    # Prometheus v2.33.4
│   ├── grafana/       # Grafana 8.4.3
│   ├── alert-manager/
│   └── prometheus-pushgateway/
└── custom/            # Custom configurations
    ├── kserve-custom/ # KServe service account (contains hardcoded MinIO address)
    └── kubeflow-custom/ # AWS/MinIO secret

docker/                # Dockerfiles (MLflow server: Python 3.8.3 + MLflow 2.4.0)
```

### 3.2 Deployment Option Overlays

```
deployment/envs/
├── kubeflow-monitoring/              # Option 1: Full Kubeflow + monitoring
├── kubeflow/                         # Option 2: Kubeflow without monitoring
├── standalone-kfp-monitoring/        # Option 3: KFP only + monitoring
├── standalone-kfp/                   # Option 4: KFP only
├── standalone-kfp-kserve-monitoring/ # Option 5: KFP + KServe + monitoring
└── standalone-kfp-kserve/            # Option 6: KFP + KServe
```

### 3.3 How setup.sh Works

1. User selects deployment option 1-6
2. Sets `DEPLOYMENT_ROOT="deployment/envs/<selected-option>"`
3. Runs `kustomize build $DEPLOYMENT_ROOT` to generate combined manifests
4. Runs `kubectl apply` to deploy

**Changing base configurations automatically affects all overlays that reference them.**

---

## 4. Service-by-Service Update Plan

Since this is a clean install upgrade, the work for each phase is: **update the relevant configuration files and manifests in the repo, then test with a fresh install on a test environment**.

Effort estimates assume: **single person + AI assistance + Kubernetes/MLOps experience**.

**Phase scope legend**:

- **[Platform-wide]** — Required for all deployment options, whether single-cloud or multi-cloud. Applies to anyone upgrading the platform.
- **[Multi-cloud only]** — Only applies when using the Liqo-based multi-cloud setup. Single-cloud deployments can skip these phases.

A single-cloud upgrade involves Phases 0-5 and 7. A multi-cloud upgrade adds Phase 6 on top.

### Phase 0: Preparation (1-2 days) [Platform-wide]

**Goal**: Understand the current deployment structure and prepare a test environment.

**Tasks**:
- Tag the current repo state in git
- Prepare a test environment (Kind cluster or VM)
- Read through `setup.sh` and the directory structure in §3

**Test Check**:
- [ ] Git tag created
- [ ] Test environment ready
- [ ] Familiar with the three-layer structure

### Phase 1: Kubernetes and Istio Configuration (3-5 days) [Platform-wide]

**Target**: Kubernetes 1.29-1.30, Istio 1.17.3 → 1.22

**What to update in the repo**:
- `deployment/kubeflow/manifests/common/`: replace all `istio-1-17` references with `istio-1-22` (matching upstream Kubeflow 1.9.1 manifests directory structure)
- Istio-related patches in `deployment/custom/`
- `ClusterSetupVerda.sh`: update recommended k3s version to 1.29-1.30 range (see note below)

**Note on Kubernetes version range [Multi-cloud constraint]**: Kubeflow 1.9 is upstream-tested against K8s 1.29 and works on 1.29-1.31. However, **Liqo 1.0.1 (used by the multi-cloud setup) only supports K8s 1.29-1.30**. Targeting K8s 1.31 would require upgrading Liqo to 1.1.x first, which is out of scope for this report. Recommendation: target 1.29 or 1.30 to keep current Liqo working. Single-cloud deployments are free to go higher but staying in this range is suggested for consistency.

**Test Check**:
- [ ] `setup.sh` fresh install succeeds with updated Istio
- [ ] All nodes Ready
- [ ] Istio ingress gateway responds

### Phase 2: Kubeflow Manifests Update (5-8 days) [Platform-wide]

**Target**: Kubeflow 1.8.0-rc.0 → 1.9.1

**What to update in the repo**:
- `deployment/kubeflow/manifests/`: replace current 1.8.0-rc.0 content with Kubeflow 1.9.1 upstream manifests (`apps/`, `common/`, `contrib/` wholesale update)
- `deployment/custom/kubeflow-custom/`: verify `aws-secret.yaml` patches still apply
- `deployment/custom/kserve-custom/`: verify `kserve-sa.yaml` (contains hardcoded MinIO address) and `kserve-deployer.yaml` (contains `serving.kserve.io` RBAC) work with KServe 0.13
- All 6 overlay `kustomization.yaml` files: update references
- Switch authentication from OIDC AuthService to oauth2-proxy 7.6.0 (Dex 2.39 stays as the IdP backing oauth2-proxy)
- Check kustomize version requirement (5.4.3+ for Kubeflow 1.9)

**Test Check**:
- [ ] `kustomize build` succeeds for all 6 deployment options
- [ ] Option 1 fresh install completes without errors
- [ ] Central Dashboard accessible (via oauth2-proxy)
- [ ] KFP UI accessible
- [ ] Can create a Notebook Server

### Phase 3: MLflow Configuration Update (2-3 days) [Platform-wide]

**Target**: MLflow 2.4.0 → 3.8.1, Python 3.8.3 → 3.10

**What to update in the repo**:
- `docker/Dockerfile`:
  - `FROM python:3.8.3` → `FROM python:3.10`
  - `ARG MLFLOW_VERSION=2.4.0` → `ARG MLFLOW_VERSION=3.8.1`
  - `boto3==1.15.16` → update to compatible version
  - `psycopg2==2.9.2` → verify compatibility with PostgreSQL 16
  - `protobuf==3.20.0` → verify compatibility with MLflow 3.8.1
- `deployment/mlflow/base/mlflow-deployment.yaml`: update image tag (currently `ghcr.io/oss-mlops-platform/mlflow_v2:0.0.2`)
- `deployment/mlflow/base/mlflow-virtualservice.yaml`: Istio 1.22 still accepts `networking.istio.io/v1beta1` (deprecated but functional). Recommended to migrate this manifest to `networking.istio.io/v1` in the same change for forward compatibility — the schema is largely identical, only the API version string changes.

**Test Check**:
- [ ] MLflow UI opens after fresh install
- [ ] Can log params and metrics
- [ ] Artifacts upload to MinIO
- [ ] `mlflow.sklearn.log_model` works
- [ ] VirtualService applies cleanly under `networking.istio.io/v1`

### Phase 4: MinIO and PostgreSQL Configuration Update (2-3 days) [Platform-wide]

**Target**: MinIO RELEASE.2023-02-10 → latest stable, PostgreSQL 13 → 16.x

**What to update in the repo**:
- `deployment/mlflow/minio/minio-deployment.yaml`: `image: minio/minio:RELEASE.2023-02-10T18-48-39Z` → update to latest stable
- `deployment/mlflow/postgres/postgres-deployment.yaml`: `image: postgres:13` → `image: postgres:16`
- `deployment/mlflow/postgres/postgres-config.yaml`: verify `POSTGRES_DB` and `POSTGRES_USER` config unchanged
- Verify MinIO S3 API compatibility with MLflow 3.8.1
- Verify MLflow 3.8.1 + psycopg2 works with PostgreSQL 16
- `deployment/custom/kserve-custom/base/kserve-sa.yaml`: verify MinIO service name remains `mlflow-minio-service.mlflow.svc.cluster.local:9000` after upgrade

**Note**: PostgreSQL 13 reached EOL in November 2025. Upgrading to 16.x is a necessary security measure.

**Test Check**:
- [ ] MinIO accessible after fresh install, buckets operational
- [ ] PostgreSQL 16 accepting connections
- [ ] MLflow can read and write to both services
- [ ] KServe service account can connect to MinIO correctly

### Phase 5: Prometheus and Grafana Configuration Update (2-3 days) [Platform-wide]

**Target**: Prometheus v2.33.4 → latest LTS, Grafana 8.4.3 → 11.x LTS

**What to update in the repo**:
- `deployment/monitoring/prometheus/prometheus-deployment.yaml`: `image: prom/prometheus:v2.33.4` → update to latest LTS
- `deployment/monitoring/grafana/grafana-deployment.yaml`: `image: grafana/grafana:8.4.3` → `image: grafana/grafana:11.x`
- `deployment/monitoring/grafana/grafana-datasource-config.yaml`: verify Prometheus datasource config format works with Grafana 11
- `deployment/monitoring/grafana/dashboards-json-config-map.yaml`: **inspect dashboard JSON for AngularJS-based panel types**. Grafana 11 disables AngularJS plugins by default. Legacy panels that need migration include:
  - `"type": "graph"` → migrate to `"type": "timeseries"`
  - `"type": "singlestat"` → migrate to `"type": "stat"`
  - `"type": "table-old"` → migrate to `"type": "table"`
  Grafana provides automatic migration when opening old dashboards in the UI; for config-as-code, do the migration in the JSON before deploying.
- `deployment/monitoring/prometheus/prometheus-config-map.yaml`: verify scrape configs work with new version

**Test Check**:
- [ ] Prometheus UI accessible and scraping targets after fresh install
- [ ] Grafana UI accessible and dashboards loading
- [ ] No "panel plugin not found" errors in Grafana logs
- [ ] Kubeflow component metrics visible

### Phase 6: Multi-Cloud Script Update (2-3 days) [Multi-cloud only]

**Goal**: Update multi-cloud setup scripts for compatibility with new versions.

**What to update**:
- `ClusterSetupVerda.sh` (`WT26H1-Multi-Cloud-Support/Scripts/`):
  - Confirm Liqo 1.0.1 compatibility with target K8s version: **Liqo 1.0.1 supports K8s 1.29-1.30**. If targeting 1.29 or 1.30, no Liqo change needed. **If the team later wants K8s 1.31, Liqo must be upgraded to 1.1.x first** (separate scope).
  - Update k3s version to 1.29-1.30
  - Ensure `ENABLE_NVIDIA_TOOLKIT` works with target k3s
- Update peering instructions to include `--resource nvidia.com/gpu=N` flag

**Test Check**:
- [ ] `ClusterSetupVerda.sh` runs successfully on fresh Verda VM
- [ ] Liqo peering works
- [ ] Offloaded namespace services visible on Verda

### Phase 7: Full Verification (1-2 days) [Platform-wide]

**Goal**: Complete fresh install + full sanity check (§6).

**Test Check**:
- [ ] All checks from §6 pass
- [ ] All 6 deployment options pass `kustomize build`

### Effort Summary

The estimates below assume **a single experienced implementer using AI assistance**. They reflect "smooth path" effort — the work needed if no major surprises occur.

| Phase | Scope | Best-case effort | Risk-adjusted effort | Risk drivers |
|-------|-------|------------------|----------------------|--------------|
| Phase 0: Preparation | Platform-wide | 1-2 days | 1-2 days | Low |
| Phase 1: K8s + Istio | Platform-wide | 3-5 days | 4-7 days | Istio crosses 5 minor versions (1.17 → 1.22); historically breaking-change-prone |
| Phase 2: Kubeflow manifests | Platform-wide | 5-8 days | 8-15 days | **Highest risk phase**: auth component swap (OIDC AuthService → oauth2-proxy), custom patches may need reworking, kustomize behavior across versions |
| Phase 3: MLflow + Dockerfile | Platform-wide | 2-3 days | 2-4 days | MLflow 2 → 3 is a major version with API changes; platform-level impact is limited |
| Phase 4: MinIO + PostgreSQL | Platform-wide | 2-3 days | 2-3 days | Low (fresh install, no data migration) |
| Phase 5: Prometheus + Grafana | Platform-wide | 2-3 days | 3-5 days | Grafana 11 disables AngularJS plugins; manual dashboard JSON migration takes time |
| Phase 6: Multi-cloud scripts | Multi-cloud only | 2-3 days | 2-3 days | Low |
| Phase 7: Full verification | Platform-wide | 1-2 days | 2-3 days | All 6 deployment options need to pass; troubleshooting any failure adds time |

**Best-case totals** (assuming smooth path):
- Single-cloud (Phases 0-5, 7): 16-26 days (~3-5 weeks)
- Multi-cloud (all phases): 18-29 days (~4-6 weeks)

**Risk-adjusted totals** (recommended for planning):
- Single-cloud (Phases 0-5, 7): **22-39 days** (~5-8 weeks)
- Multi-cloud (all phases): **24-42 days** (~5-8.5 weeks)

**Estimation methodology**: Per-phase numbers are derived from typical complexity factors — number of manifest files touched, presence of breaking changes between versions, scope of custom patches that need re-validation, and the count of integration points to test. The risk-adjusted column adds buffer for the two empirically high-risk phases (Phase 2 Kubeflow upgrade, Phase 5 Grafana 11 migration) where prior community experience consistently shows the smooth-path estimate is optimistic.

**Confidence level**: Best-case numbers are best treated as a lower bound for project planning. The risk-adjusted range is the more realistic budget. **A summer time window of 8-10 weeks comfortably accommodates the multi-cloud upgrade with risk buffer**; a tighter 4-week window only works in the best-case scenario, which should not be the planning baseline.

---

## 5. Adapting setup.sh

`setup.sh` is a wrapper around `kustomize build` + `kubectl apply`. Likely needs minimal changes:
- Check disk space / CPU recommendations
- Check kustomize version requirement (5.4.3+ for Kubeflow 1.9)
- Verify Kind cluster creation with target Kubernetes version

Testing strategy:
- **Must pass kustomize build**: all 6 options
- **Must test fresh install**: option 1 (kubeflow-monitoring)
- **Can leave for next team**: other options on different infrastructure

---

## 6. Sanity Check Procedures

Run after completing all configuration updates and doing a fresh install (Phase 7).

### 6.1 Cluster Health

```bash
kubectl get pods --all-namespaces | grep -v "Running\|Completed"
kubectl get nodes
kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount' | tail -20
```

### 6.2 Kubeflow Core

- Central Dashboard login works (via oauth2-proxy)
- Can create Notebook Server
- KFP UI accessible

### 6.3 MLflow

- MLflow UI opens
- Can log params, metrics, artifacts
- PostgreSQL backend stores metadata
- MinIO stores artifacts

### 6.4 Pipeline

- Wine quality pipeline runs to completion
- MLflow shows corresponding run
- KServe inference service responds

### 6.5 Monitoring (Options 1, 3, 5)

- Prometheus scraping targets
- Grafana dashboards loading

### 6.6 Multi-Cloud

- Liqo peering healthy
- Pipeline completes in multi-cloud mode

### 6.7 Deployment Option Build Test

```bash
for opt in kubeflow-monitoring kubeflow standalone-kfp-monitoring standalone-kfp standalone-kfp-kserve-monitoring standalone-kfp-kserve; do
  echo "Testing $opt..."
  kustomize build deployment/envs/$opt > /dev/null && echo "  PASS" || echo "  FAIL"
done
```

---

## 7. Key Decisions

### 7.1 Pipeline Code Migration Is Separate Work

Platform services run in separate pods with their own Python environments. Updating service versions in deployment configuration does not affect pipeline code. See Appendix C.

### 7.2 About Verda API [Multi-cloud only]

Verda (formerly DataCrunch) has a programmatic API. The previous team's tickets #7 and #10 confirm the API supports passing startup scripts during VM creation.

- REST API: https://api.datacrunch.io/v1/docs
- Python SDK: https://github.com/verda-cloud/sdk-python
- Authentication: OAuth 2.0 via https://console.verda.com

---

## 8. Verification Status of Pre-Start Items

### 8.1 Resolved Through Research

The following items were flagged in earlier drafts as "to be verified before starting." They have been resolved via documentation review (Kubeflow 1.9.1 manifests README, Liqo docs, Grafana 11 release notes, Istio 1.22 reference).

1. **Knative, Cert Manager, KFP versions bundled with Kubeflow 1.9.1** — Resolved.
   - Knative Serving + Eventing: **1.12**
   - Cert Manager: **1.14**
   - KFP backend uses Argo Workflows **3.4**
   - Authentication: oauth2-proxy **7.6.0** (Dex **2.39** stays as IdP backing oauth2-proxy)
   - Kubeflow 1.9.1 was tested upstream against Kubernetes **1.29**.

2. **Liqo 1.0.1 compatibility with target Kubernetes** — Resolved. Liqo 1.0.1 supports K8s 1.29-1.30; 1.31 would require Liqo 1.1.x. See the [Multi-cloud constraint] note in §2.1 and Phase 1 for full details.

3. **Grafana 8.4.3 → 11.x dashboard JSON migration** — Resolved.
   - Grafana 11 **disables AngularJS-based plugins by default**.
   - Affected panel types in dashboard JSON: `graph` → `timeseries`, `singlestat` → `stat`, `table-old` → `table`.
   - The dashboard JSON in `deployment/monitoring/grafana/dashboards-json-config-map.yaml` should be inspected for these legacy panel types and migrated before deploying. Reflected in Phase 5.

4. **`mlflow-virtualservice.yaml`'s `networking.istio.io/v1beta1` API in Istio 1.22** — Resolved.
   - Istio 1.22 **still accepts** `v1beta1` (it is deprecated but functional, no breaking change).
   - Recommendation: migrate to `networking.istio.io/v1` in the same upgrade — the schema is largely identical, only the API version string changes. Reflected in Phase 3.

### 8.2 To Be Verified On-Cluster

1. **Current Kubernetes version on cPouta and Verda** — Cannot be confirmed from repo files. The summer implementer should run `kubectl version` on each cluster and check the `Server Version` line. cPouta runs **KIND (Kubernetes in Docker)** as the Consumer cluster; Verda runs **k3s** as the Provider cluster. Both report their underlying Kubernetes version through the same command. If either is already at 1.29-1.30, the K8s upgrade work in Phase 1 may not be needed for that cluster; otherwise follow Phase 1 to bring it into the target range.

### 8.3 Follow-Up Work (Not in This Scope)

1. Pipeline code KFP v1→v2 migration (see Appendix C)
2. Hardcoded address parameterization (#53, #54)
3. Runner in-cluster setup — Tran Anh and Roope PoC
4. Auto scaling investigation (#63)
5. Liqo 1.0.1 → 1.1.x upgrade [Multi-cloud only] (only needed if the team later targets K8s 1.31)

---

## 9. Getting Started Guide for the Next Team

1. Read `https://mlops-explained.lovable.app` for platform architecture
2. Read closed issues #43 / #44 / #51 on GitHub for our team's work
3. Then read this report, starting with §3 (repo structure)

---

## Appendix A: Glossary

- **LTS (Long-Term Support)**: a software release with a longer maintenance cycle
- **Service Reflection**: a Liqo feature that mirrors services across clusters
- **Kustomize Overlay**: Kubernetes configuration via layered customizations
- **Clean Install**: fresh installation with new versions, no data carried over
- **CRD (Custom Resource Definition)**: Kubernetes extension mechanism
- **oauth2-proxy**: authentication proxy used by Kubeflow 1.9+ (replaces OIDC AuthService)
- **Dex**: OIDC identity provider; in Kubeflow 1.9 it sits behind oauth2-proxy as the IdP
- **AngularJS plugins**: Grafana's legacy plugin runtime, disabled by default in Grafana 11
- **EOL (End of Life)**: software no longer receiving maintenance or security updates

## Appendix B: References

- Kubeflow 1.9 release blog: https://blog.kubeflow.org/kubeflow-1.9-release/
- Kubeflow manifests (v1.9.1) and version matrix: https://github.com/kubeflow/manifests/tree/v1.9.1-branch
- MLflow 3.8.1: https://github.com/mlflow/mlflow/releases/tag/v3.8.1
- Liqo documentation: https://docs.liqo.io
- Liqo Kubernetes compatibility matrix: https://docs.liqo.io/en/v1.0.1/installation/requirements.html
- Liqo GPU peering: https://github.com/liqotech/liqo/blob/master/docs/usage/peer.md
- Verda API: https://api.datacrunch.io/v1/docs
- Verda Python SDK: https://github.com/verda-cloud/sdk-python
- OSS MLOps Platform repo: https://github.com/OSS-MLOPS-PLATFORM/oss-mlops-platform
- Our multi-cloud repo: https://github.com/Softala-MLOPS/WT26H1-Multi-Cloud-Support
- Our documentation: https://mlops-explained.lovable.app
- PostgreSQL 16 release: https://www.postgresql.org/about/news/postgresql-16-released-2715/
- Prometheus LTS releases: https://prometheus.io/docs/introduction/release-cycle/
- Grafana 11 releases: https://grafana.com/docs/grafana/latest/release-notes/
- Grafana AngularJS deprecation: https://grafana.com/docs/grafana/latest/developers/angular_deprecation/
- Istio 1.22 networking API: https://istio.io/latest/docs/reference/config/networking/virtual-service/
- oauth2-proxy 7.6.0 release: https://github.com/oauth2-proxy/oauth2-proxy/releases/tag/v7.6.0

## Appendix C: Pipeline Code KFP v1→v2 Migration (Separate Project)

This is **not part of the platform upgrade**.

Pipeline code is located at `tools/CLI-tool/files/development/notebooks/demo-pipeline.ipynb` and `tools/CLI-tool/Components/` (Dev and Prod component YAML sets).

**What needs to change**:
- `@component` decorator rewrite (v2 type system)
- `Input[Dataset]` / `Output[Artifact]` replace v1 path-based passing
- `dsl.Condition` rewritten for v2 syntax
- `kfp.aws.use_aws_secret` replaced with v2 secret injection
- Pipeline submission method changed to v2 client API
- Hardcoded addresses (#43) parameterized
- `packages_to_install`: `mlflow~=2.4.1` → `mlflow~=3.8.1`
- `packages_to_install`: `kserve==0.11.0` → `kserve==0.13.x`

**Estimated effort**: 10-15 days (single person + AI assistance)

**Why it is separate**: Each service runs in its own pod with its own Python environment. Updating MLflow from 2.4.0 to 3.8.1 in the deployment configuration does not require pipeline code to change.
