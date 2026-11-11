# Intent Classifier Model

This small project demonstrates:
- Training a tiny text classifier.
- Saving the model artifact.
- Serving predictions via a Flask API (`/predict`).

## Quick start (local)
1. Create a virtualenv and install:
    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt

2. Train the model:
    python model/train.py
    This will create `model/artifacts/intent_model.pkl`.

3. Run the API:
    python app.py
    The API will be available at http://127.0.0.1:6000

4. Example request:
    curl -X POST http://localhost:6000/predict -H "Content-Type: application/json" -d '{"text":"whatsapp"}'

    Response:
    {
        "intent": "complaint",
        "probabilities": {"complaint": 0.85, "question": 0.05, ...}
    }


## Quick start (EC2 Auto Scaling Group)

1. **Create a Launch Template:**
   Select an **Ubuntu Server** AMI, allow inbound **HTTP (port 80)** in the Security Group, and paste the contents of `userdata.sh` into **Advanced details → User data**.

2. **Create an Application Load Balancer (ALB) & Target Group:**
   Create an HTTP Target Group on **port 80** with the health check path set to `/health`, and attach it to an internet-facing ALB.

3. **Launch the Auto Scaling Group (ASG):**
   Create an ASG using your Launch Template, attach it to your Target Group, and access the web UI or `/predict` endpoint via your **ALB DNS name**.
