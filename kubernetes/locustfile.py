from locust import HttpUser, task, between
import json
import os

MODEL_NAME = os.environ.get("MODEL_NAME", "Qwen/Qwen2.5-1.5B-Instruct")
# Prefer INGRESS_HOST_PORT from the environment; default matches config.env.
INGRESS_HOST_PORT = os.environ.get("INGRESS_HOST_PORT", "8080")


class VLLMUser(HttpUser):
    """Load generator aimed at the Kind Ingress front door (production-shaped entrypoint)."""

    host = f"http://localhost:{INGRESS_HOST_PORT}"
    wait_time = between(1, 3)

    @task
    def chat_completion(self):
        payload = {
            "model": MODEL_NAME,
            "messages": [
                {"role": "system", "content": "You are a helpful assistant."},
                {
                    "role": "user",
                    "content": "Explain Kubernetes Horizontal Pod Autoscaling in two sentences.",
                },
            ],
            "max_tokens": 80,
            "temperature": 0.2,
            "stream": False,
        }
        headers = {"Content-Type": "application/json"}

        with self.client.post(
            "/v1/chat/completions",
            data=json.dumps(payload),
            headers=headers,
            name="K8s Chat Completion",
            catch_response=True,
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(
                    f"status={response.status_code} body={response.text[:200]}"
                )
