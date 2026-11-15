# Deploy Intent Classifier Model on Amazon EKS

End-to-end guide to build the Docker image, push it to Docker Hub, provision an Amazon EKS cluster (via **AWS Console** or **CloudShell**), deploy the application, and clean up resources.

---

## 1. Build & Push Docker Image to Docker Hub

```bash
# Build the image from the Dockerfile
docker build -t abdueissa/intent-classifier-model:latest .

# Test locally on port 8080 -> 6000
docker run -d -p 8080:6000 --name intent-app abdueissa/intent-classifier-model:latest
docker ps

# Stop local test container
docker rm -f intent-app

# Log in and push to Docker Hub
docker login
docker push abdueissa/intent-classifier-model:latest
```

---

## 2. Create Amazon EKS Cluster (Choose One Method)

### Method A: Create EKS Cluster via AWS Console
1. Open the **Amazon EKS Console** and choose your region (e.g., `eu-north-1` or `us-east-1`).
2. Click **Add cluster** > **Create**.
3. Keep **Quick configuration (EKS Auto Mode)** selected:
   - **Name**: `intent-classifier-model`
   - **Kubernetes version**: Keep default (`1.37`)
   - **IAM roles / VPC / Subnets**: Keep default auto-generated settings
4. Click **Create** and wait **10–15 minutes** until status becomes **Active**.
5. Open **AWS CloudShell** (`>_` icon in top toolbar) and connect `kubectl`:
   ```bash
   aws eks update-kubeconfig --region eu-north-1 --name intent-classifier-model
   ```

### Method B: Create EKS Cluster via AWS CloudShell (1 Command)
Open **AWS CloudShell** and run:

```bash
eksctl create cluster \
  --name intent-classifier-model \
  --region eu-north-1 \
  --version 1.32 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed
```

---

## 3. Deploy the Docker Image to EKS

Run the following in **AWS CloudShell** to deploy the container and expose it publicly on port `8080`:

```bash
cat <<EOF > deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: intent-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: intent-app
  template:
    metadata:
      labels:
        app: intent-app
    spec:
      containers:
        - name: intent-app
          image: abdueissa/intent-classifier-model:latest
          ports:
            - containerPort: 6000
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "1000m"
              memory: "2Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: intent-app-service
spec:
  type: LoadBalancer
  selector:
    app: intent-app
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 6000
EOF

kubectl apply -f deployment.yaml
```

### Verify & Get Public URL
```bash
# Wait until pod status is Running
kubectl get pods -w

# Get the external LoadBalancer URL
kubectl get svc intent-app-service
```
Access your app at `http://<EXTERNAL-IP>:8080`.

---

## 4. Cleanup / Delete Cluster (Stop Billing)

First delete the Kubernetes service so AWS removes the Load Balancer:
```bash
kubectl delete -f deployment.yaml
```

Then delete the EKS cluster using the method you used to create it:

### Option A: Delete via AWS Console
1. Open the **Amazon EKS Console** > **Clusters**.
2. Select **`intent-classifier-model`**.
3. Click **Delete** (top right), type the cluster name to confirm, and click **Delete**.

### Option B: Delete via AWS CloudShell (1 Command)
```bash
eksctl delete cluster --name intent-classifier-model --region eu-north-1
```
