# Customizes the base hello-world image for the application ECS task (req. 11)
# Build context must be the repo root so the COPY below can reach scripts/:
#   docker build -f Docker/Dockerfile -t cloud-app:<tag> .
FROM infrastructureascode/hello-world:latest

# Port 80 matches container_port in modules/ecs_service/variables.tf and
# the ALB target group port defined in alb.tf
ENV PORT=80
EXPOSE 80

# Health check script — the script flaw lives here (see scripts/verify_health.sh)
COPY --chmod=755 scripts/verify_health.sh /usr/local/bin/verify_health.sh

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD /usr/local/bin/verify_health.sh || exit 1
