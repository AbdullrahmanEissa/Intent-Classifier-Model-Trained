# Intent Classifier Model — Amazon EKS Deployment

## 1. Build & Push Docker Image
```bash
docker build -t abdueissa/intent-classifier-model:latest .
docker login
docker push abdueissa/intent-classifier-model:latest
```

## 2. Create Amazon EKS Cluster

### Option A: AWS Console
1. Open **Amazon EKS Console** (`eu-north-1`) > **Add cluster** > **Create**.
2. Keep **Quick configuration (EKS Auto Mode)**, name it `intent-classifier-model`, and click **Create**.
3. Wait until status is **Active**, then connect CloudShell:
4. Subnet Tagging Neeeded
```bash
aws eks update-kubeconfig --region eu-north-1 --name intent-classifier-model
```

### Option B: AWS CloudShell
```bash
nohup eksctl create cluster \
  --name intent-classifier-model \
  --region eu-north-1 \
  --version 1.32 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed > eks.log 2>&1 &

or Just 

nohub eksctl create cluster --name intent-classifier-model --region eu-north-1 --managed

```

## 3. Deploy Manifests via CloudShell
```bash
git clone https://github.com
cd Intent-Classifier-Model-Trained
kubectl apply -f k8s-manifests/namespace.yml
kubectl apply -f k8s-manifests/
```

## 4. Serve & Test the Model
```bash
kubectl get all -n intent-classifier
kubectl get svc intent-app-service -n intent-classifier
```

```bash
curl -X POST http://<EXTERNAL-IP>/predict \
  -H "Content-Type: application/json" \
  -d '{"text": "hello"}'
```

## 5. Delete Cluster

### Option A: AWS Console
```bash
kubectl delete -f k8s-manifests/
```
Then open **EKS Console** > **`intent-classifier-model`** > **Delete**.

### Option B: AWS CloudShell
```bash
kubectl delete -f k8s-manifests/
eksctl delete cluster --name intent-classifier-model --region eu-north-1
```
