from locust import HttpUser, task, between
import json

class VLLMUser(HttpUser):
    host = "http://127.0.0.1:8000"
    # The user waits between 1 and 3 seconds after each task before executing the next one
    wait_time = between(1, 3)

    @task
    def generate_text(self):
        """
        Simulates a user sending a chat completion request.
        By setting stream=True in the payload, we can track Time To First Token (TTFT).
        """
        payload = {
            "model": "mlx-community/gemma-4-31B-it-OptiQ-4bit",
            "messages": [
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": "Explain the concept of unified memory in Apple Silicon."}
            ],
            "max_tokens": 150,
            "stream": False # We set to False for simple throughput load testing, use True if implementing a custom TTFT client
        }
        
        headers = {
            "Content-Type": "application/json"
        }

        # We group all requests to this endpoint under a single name in Locust UI
        with self.client.post("/v1/chat/completions", data=json.dumps(payload), headers=headers, name="Chat Completion", catch_response=True) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Failed with status code: {response.status_code}")
