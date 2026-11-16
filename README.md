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
3. Tag your default VPC subnets with `kubernetes.io/role/elb=1` so the LoadBalancer resolves an External IP:
```bash
VPC_ID=\$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text --region eu-north-1)
SUBNET_IDS=(aws ec2 describe-subnets --filters Name=vpc-id,Values=VPC_ID --query "Subnets[*].SubnetId" --output text --region eu-north-1)
aws ec2 create-tags --resources \$SUBNET_IDS --tags Key=kubernetes.io/role/elb,Value=1 --region eu-north-1
aws eks update-kubeconfig --region eu-north-1 --name intent-classifier-model
```

### Option B: AWS CloudShell (`nohup` Background Execution)
Using `t3.micro` (4 nodes to fit system + app pods within the 4-pod/node ENI limit):
```bash
nohup eksctl create cluster \
  --name intent-classifier-model \
  --region eu-north-1 \
  --version 1.32 \
  --nodegroup-name standard-workers \
  --node-type t3.micro \
  --nodes 4 \
  --nodes-min 2 \
  --nodes-max 5 \
  --managed > eks.log 2>&1 &

tail -f eks.log
```

Or using `t3.small` (2 nodes, 11 pods/node):
```bash
nohup eksctl create cluster \
  --name intent-classifier-model \
  --region eu-north-1 \
  --version 1.32 \
  --nodegroup-name standard-workers \
  --node-type t3.small \
  --nodes 2 \
  --managed > eks.log 2>&1 &

tail -f eks.log
```

## 3. Deploy Manifests via CloudShell
```bash
git clone -b Kubernetes https://github.com
cd Intent-Classifier-Model-Trained/k8s-manifests
kubectl apply -f namespace.yaml
kubectl apply -f .
```

## 4. Serve & Test the Model
```bash
kubectl get pods -n intent-classifier -w
kubectl get svc intent-app-service -n intent-classifier -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

```bash
curl -X POST http://<EXTERNAL-IP>/predict \
  -H "Content-Type: application/json" \
  -d '{"text": "hello"}'
```

## 5. Delete Cluster

### Option A: AWS Console
```bash
kubectl delete namespace intent-classifier
```
Then open **EKS Console** > **`intent-classifier-model`** > **Delete**.

### Option B: AWS CloudShell
```bash
kubectl delete namespace intent-classifier
nohup eksctl delete cluster --name intent-classifier-model --region eu-north-1 --disable-nodegroup-eviction > delete.log 2>&1 &
tail -f delete.log
```
