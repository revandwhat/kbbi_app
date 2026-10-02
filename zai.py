import os
import requests

api_key = os.environ["ZAI_API_KEY"]

url = "https://api.z.ai/api/paas/v4/chat/completions"

headers = {
    "Authorization": f"Bearer {api_key}",
    "Content-Type": "application/json"
}

data = {
    "model": "glm-5.3-flash",
    "messages": [
        {
            "role": "user",
            "content": "Halo! Apakah kamu bisa bekerja?"
        }
    ]
}

response = requests.post(
    url,
    headers=headers,
    json=data
)

print(response.status_code)
print(response.text)
