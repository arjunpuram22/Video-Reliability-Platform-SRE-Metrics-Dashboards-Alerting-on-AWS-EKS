from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import redis
import json
import time

from prometheus_client import Counter, Gauge, generate_latest
from fastapi.responses import Response

app = FastAPI()

# Redis connection
redis_client = redis.Redis(host="redis", port=6379, decode_responses=True)

# Metrics
upload_requests_total = Counter(
    "upload_requests_total", "Total upload requests")
upload_failures_total = Counter(
    "upload_failures_total", "Total upload failures")
queue_depth_gauge = Gauge("queue_depth", "Current queue depth")


class VideoJob(BaseModel):
    video_id: str
    duration: int
    quality: str


@app.get("/")
def root():
    return {"message": "Upload Service Running"}


@app.post("/upload")
def upload_video(job: VideoJob):
    try:
        upload_requests_total.inc()

        job_data = {
            "video_id": job.video_id,
            "duration": job.duration,
            "quality": job.quality,
            "timestamp": time.time()
        }

        redis_client.rpush("video_jobs", json.dumps(job_data))

        queue_size = redis_client.llen("video_jobs")
        queue_depth_gauge.set(queue_size)

        return {
            "status": "accepted",
            "queue_depth": queue_size
        }

    except Exception as e:
        upload_failures_total.inc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type="text/plain")
