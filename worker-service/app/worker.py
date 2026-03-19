import redis
import json
import time
import random

from prometheus_client import Counter, Gauge, Histogram, start_http_server

print("Worker booting...", flush=True)

# Wait for Redis to be ready
while True:
    try:
        redis_client = redis.Redis(
            host="redis", port=6379, decode_responses=True)
        redis_client.ping()
        print("Connected to Redis", flush=True)
        break
    except Exception:
        print("Waiting for Redis...", flush=True)
        time.sleep(2)

# Metrics
jobs_processed_total = Counter("jobs_processed_total", "Total processed jobs")
worker_active_jobs = Gauge("worker_active_jobs", "Current active jobs")
job_processing_seconds = Histogram("job_processing_seconds", "Processing time")
worker_failures_total = Counter("worker_failures_total", "Worker failures")

start_http_server(8001)

while True:
    try:
        job = redis_client.lpop("video_jobs")

        if job:
            worker_active_jobs.inc()

            job_data = json.loads(job)
            processing_time = random.randint(2, 6)

            print(
                f"Processing {job_data['video_id']} for {processing_time}s", flush=True)

            start = time.time()
            time.sleep(processing_time)
            end = time.time()

            job_processing_seconds.observe(end - start)
            jobs_processed_total.inc()
            worker_active_jobs.dec()

            print(f"Finished {job_data['video_id']}", flush=True)

        else:
            time.sleep(1)

    except Exception as e:
        worker_failures_total.inc()
        print(f"Worker error: {e}", flush=True)
        time.sleep(2)
