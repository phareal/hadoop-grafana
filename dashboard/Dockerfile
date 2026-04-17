FROM python:3.11-alpine
WORKDIR /app
RUN apk add --no-cache --virtual .build gcc musl-dev linux-headers \
    && pip install --no-cache-dir --upgrade pip
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && apk del .build
COPY . .
EXPOSE 5000
CMD ["python", "-u", "app.py"]
