# Wraps the base hello-world image for our app's ECS task.
# Build from the repo root, not this Docker/ folder, so the COPY below can see scripts/:
#   docker build -f Docker/Dockerfile -t cloud-app:<tag> .
FROM infrastructureascode/hello-world:latest

# Has to match container_port in modules/ecs_service/variables.tf and the
# target group port in alb.tf, or the ALB health checks will fail silently
ENV PORT=80
EXPOSE 80

# This is the script with FLAW 3 in it — see scripts/verify_health.sh for details
COPY --chmod=755 scripts/verify_health.sh /usr/local/bin/verify_health.sh

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD /usr/local/bin/verify_health.sh || exit 1
