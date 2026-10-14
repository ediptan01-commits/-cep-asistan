import os
from datetime import date
from collections import defaultdict
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel, Field
import httpx

app = FastAPI(title="CepAsistan AI API", version="1.0.0")
AI_API_KEY = os.getenv("AI_API_KEY", "")
AI_BASE_URL = os.getenv("AI_BASE_URL", "https://api.openai.com/v1/chat/completions")
AI_MODEL = os.getenv("AI_MODEL", "gpt-4o-mini")
# Starter demo quota is in-memory and resets when the server restarts. Use Redis/database + authenticated users in production.
usage = defaultdict(int)

class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=8000)
    pro: bool = False

@app.get("/health")
def health():
    return {"status": "ok", "service": "CepAsistan AI"}

@app.post("/chat")
async def chat(body: ChatRequest, x_user_id: str = Header(default="anonymous")):
    if not AI_API_KEY:
        raise HTTPException(status_code=503, detail="AI_API_KEY sunucuda tanımlanmamış")
    user_key = f"{x_user_id}:{date.today().isoformat()}"
    limit = 100 if body.pro else 5
    if usage[user_key] >= limit:
        raise HTTPException(status_code=429, detail="Günlük kullanım kotası doldu")
    payload = {
        "model": AI_MODEL,
        "messages": [
            {"role": "system", "content": "Türkçe yanıt veren, güvenli ve yardımcı bir günlük yaşam asistanısın. Belirsizlikleri açıkça belirt."},
            {"role": "user", "content": body.message},
        ],
        "max_tokens": 900,
    }
    async with httpx.AsyncClient(timeout=45) as client:
        try:
            response = await client.post(AI_BASE_URL, headers={"Authorization": f"Bearer {AI_API_KEY}", "Content-Type": "application/json"}, json=payload)
        except httpx.HTTPError:
            raise HTTPException(status_code=502, detail="AI sağlayıcısına bağlanılamadı")
    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail="AI sağlayıcısı hata döndürdü")
    data = response.json()
    reply = data.get("choices", [{}])[0].get("message", {}).get("content", "Yanıt alınamadı")
    usage[user_key] += 1
    return {"reply": reply, "remaining": max(0, limit - usage[user_key]), "limit": limit}
