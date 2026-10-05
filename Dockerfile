FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir flask gunicorn pywebpush
COPY napper.py app.py store.py push.py who.py index.html sw.js ./
# 1 worker: baggrundstråden (sensor + notifikationer) må kun køre ét sted
CMD ["gunicorn", "-b", "0.0.0.0:8080", "-w", "1", "--threads", "4", "app:app"]
