FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY generate_logs.py .
CMD ["python", "-u", "generate_logs.py"]
