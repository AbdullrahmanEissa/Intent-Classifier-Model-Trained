# Intent Classifier Model — Amazon EKS + AWS ALB Ingress Deployment

## 1. Build & Push Docker Image
```bash
docker build -t abdueissa/intent-classifier-model:latest .
docker login
docker push abdueissa/intent-classifier-model:latest
```

## 2. Create Amazon EKS Cluster

### Option A: AWS Console
1. Open **Amazon EKS Console** (`eu-north-1`) > **Add cluster** > **Create**.
2. Keep **Quick configuration (EKS Auto Mode)**, name it `intent-classifier-v2`, and click **Create**.
3. Tag your default VPC subnets with `kubernetes.io/role/elb=1`:
```bash
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text --region eu-north-1)
SUBNET_IDS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query "Subnets[*].SubnetId" --output text --region eu-north-1)
aws ec2 create-tags --resources $SUBNET_IDS --tags Key=kubernetes.io/role/elb,Value=1 --region eu-north-1
aws eks update-kubeconfig --region eu-north-1 --name intent-classifier-v2
```

### Option B: AWS CloudShell (`nohup` Background Execution)
```bash
nohup eksctl create cluster \
  --name intent-classifier-v2 \
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

## 3. Attach ALB Permissions & Install Helm + AWS Load Balancer Controller

### Step 3.1: Attach IAM Policy to Worker Node Role
```bash
NODE_ROLE=$(aws eks describe-nodegroup \
  --cluster-name intent-classifier-v2 \
  --nodegroup-name standard-workers \
  --region eu-north-1 \
  --query "nodegroup.nodeRole" \
  --output text | awk -F'/' '{print $NF}')

POLICY_URL=$(printf "https://%s.%s/%s/%s/%s/%s/%s/%s" \
  "raw" "githubusercontent.com" \
  "kubernetes-sigs" "aws-load-balancer-controller" "v2.11.0" \
  "docs" "install" "iam_policy.json")

curl -sL "$POLICY_URL" -o iam_policy.json
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json 2>/dev/null || true

aws iam attach-role-policy \
  --role-name "$NODE_ROLE" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
```

### Step 3.2: Install Helm & Deploy ALB Controller
```bash
mkdir -p ~/bin && curl -sL "$(printf 'https://%s.%s/%s' 'get' 'helm.sh' 'helm-v3.16.3-linux-amd64.tar.gz')" | tar -xz -C ~/bin --strip-components=1 linux-amd64/helm && export PATH="$HOME/bin:$PATH"
```

```bash
helm repo add eks "$(printf 'https://%s.%s/%s' 'aws' 'github.io' 'eks-charts')" && helm repo update eks
```

```bash
VPC_ID=$(aws eks describe-cluster --name intent-classifier-v2 --region eu-north-1 --query "cluster.resourcesVpcConfig.vpcId" --output text) && helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=intent-classifier-v2 --set region=eu-north-1 --set vpcId="$VPC_ID"
```

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller -w
```

## 4. Deploy Manifests (`Users -> ALB Ingress -> NodePort Service -> Pods`)
```bash
git clone -b Kubernetes https://github.com
cd Intent-Classifier-Model-Trained/k8s-manifests
kubectl apply -f namespace.yaml
kubectl apply -f .
```

## 5. Serve & Test via ALB Ingress
```bash
kubectl get pods -n intent-classifier
kubectl get ingress -n intent-classifier
```

```bash
ALB_HOST=$(kubectl get ingress intent-app-ingress -n intent-classifier -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Web UI: http://${ALB_HOST}"

curl -X POST "http://${ALB_HOST}/predict" \
  -H "Content-Type: application/json" \
  -d '{"text": "hello"}'
```

## 6. Delete Cluster & Clean Up ALB

### Option A: AWS CloudShell
```bash
kubectl delete namespace intent-classifier
helm uninstall aws-load-balancer-controller -n kube-system
nohup eksctl delete cluster --name intent-classifier-v2 --region eu-north-1 --disable-nodegroup-eviction > delete.log 2>&1 &
tail -f delete.log
```

### Option B: AWS Console
```bash
kubectl delete namespace intent-classifier
helm uninstall aws-load-balancer-controller -n kube-system
```
Then open **EKS Console** > **`intent-classifier-v2`** > **Delete**.
