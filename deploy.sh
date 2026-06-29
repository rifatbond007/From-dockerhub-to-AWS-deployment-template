#!/bin/bash
set -e

# ============================================
# EC2 Deployment Script (manual fallback)
# Run this on the EC2 instance or via SSH
# ============================================

IMAGE="$1"
if [ -z "$IMAGE" ]; then
  echo "Usage: ./deploy.sh <docker-image-tag>"
  echo "Example: ./deploy.sh username/my-app:latest"
  exit 1
fi

CONTAINER_NAME=$(basename "$IMAGE" | cut -d: -f1)

echo "Pulling image: $IMAGE"
docker pull "$IMAGE"

echo "Stopping existing container..."
docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1 && \
  docker stop "$CONTAINER_NAME" && \
  docker rm "$CONTAINER_NAME" || true

echo "Starting new container..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p 3000:3000 \
  "$IMAGE"

echo "Cleaning up old images..."
docker image prune -af --filter "until=24h"

echo "Deployment complete!"
