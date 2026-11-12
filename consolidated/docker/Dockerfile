FROM alpine:latest
RUN apk update && apk add --no-cache python3 py3-pip nodejs npm git curl build-base
WORKDIR /app
CMD ["python3", "hermes/main.py"]
