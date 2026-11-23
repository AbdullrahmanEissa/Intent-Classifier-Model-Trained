# Intent Classifier Model — KServe Deployment on Kind

Deploying a containerized Intent Classifier model (`abdueissa/intent-classifier-model:latest`) on a local **Kind** Kubernetes cluster using **KServe** in `RawDeployment` mode.

---

## 1. Why KServe Over Standard Kubernetes (`Deployment + Service`)?

| Feature | Standard Kubernetes (`Deployment`) | **KServe (`InferenceService`)** |
| :--- | :--- | :--- |
| **Configuration Simplicity** | Requires separate `Deployment`, `Service`, `Ingress`, and `HPA` manifests | Single `InferenceService` manifest generates all required resources automatically |
| **Scale to Zero** | Pods stay running and consume RAM/CPU even when idle | Automatically scales down to `0` pods during idle periods (in Serverless mode) |
| **Canary Rollouts** | Requires complex Ingress/Service mesh routing rules | Native traffic splitting (e.g., `canaryTrafficPercent: 20`) |
| **Model Storage Decoupling** | Model artifacts must be baked into the Docker image | Pulls model artifacts directly from S3, GCS, or PVCs using built-in runtimes |
| **Production ML Features** | Must implement batching and metrics manually in app code | Built-in request batching, payload logging, and Prometheus metrics |

---

## 2. What is Knative & Why `RawDeployment` Mode?

**Knative** is a Kubernetes extension that enables **Serverless** workloads (similar to AWS Lambda) inside a cluster—providing **Scale to Zero**, request-based autoscaling (concurrency), and traffic splitting.

KServe supports two deployment modes:

| Comparison | **Serverless Mode (with Knative)** | **RawDeployment Mode (Used Here)** |
| :--- | :--- | :--- |
| **Underlying Resources** | Creates a `Knative Service` + requires **Istio** or **Kourier** networking | Creates standard Kubernetes resources (`Deployment`, `Service`, `HPA`) |
| **Resource Overhead** | **Heavy** (~4–6 GB RAM overhead for Knative + Istio) | **Lightweight** (only requires KServe + `cert-manager`) |
| **Scale to Zero (`0` Pods)** | Supported | Not supported (minimum `1` replica stays running) |
| **Canary Traffic Splitting** | Supported natively | Not supported natively |
| **Local Kind Suitability** | Complex networking and high resource usage locally | Fast, simple, and works directly with `kubectl port-forward` |

We use **`RawDeployment`** here because it avoids heavy Istio/Knative overhead on a local Kind cluster while keeping KServe's unified `InferenceService` abstraction.

---

## 3. Prerequisites
- Docker
- `kind`
- `kubectl`
- `helm`

---

## 4. Installation & Setup

### Step 1: Create Local Kind Cluster
```bash
kind create cluster --name kserve
kubectl cluster-info --context kind-kserve
```

### Step 2: Install `cert-manager`
```bash
helm install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.16.2 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

### Step 3: Install KServe (`RawDeployment` Mode)
```bash
KSERVE_VERSION=v0.14.1

helm install kserve-crd oci://ghcr.io/kserve/charts/kserve-crd \
  --version \$KSERVE_VERSION \
  --namespace kserve \
  --create-namespace

helm install kserve oci://ghcr.io/kserve/charts/kserve \
  --version \$KSERVE_VERSION \
  --namespace kserve \
  --set kserve.controller.deploymentMode=RawDeployment
```

Verify KServe pods are running:
```bash
kubectl get pods -n kserve -w
```

---

## 5. Deploy the Model (`InferenceService`)

Create a namespace and save the manifest as `intent-isvc.yaml`:

```bash
kubectl create namespace intent-kserve

cat <<'EOF' > intent-isvc.yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: intent-classifier
  namespace: intent-kserve
spec:
  predictor:
    containers:
      - name: kserve-container
        image: abdueissa/intent-classifier-model:latest
        ports:
          - containerPort: 6000
            protocol: TCP
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "384Mi"
EOF

kubectl apply -f intent-isvc.yaml
```

Wait until `READY` becomes `True`:
```bash
kubectl get inferenceservice -n intent-kserve -w
```

---

## 6. Serve & Test Locally

Forward the predictor service port to `8080`:
```bash
kubectl port-forward -n intent-kserve svc/intent-classifier-predictor 8080:80
```

- **Web UI**: Open `http://localhost:8080` in your browser.
- **API Inference (`curl`)**:
```bash
curl -X POST http://localhost:8080/predict \
  -H "Content-Type: application/json" \
  -d '{"text": "hello"}'
```

---

## 7. Cleanup
```bash
kind delete cluster --name kserve
```
