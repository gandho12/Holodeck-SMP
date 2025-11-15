# Multi-stage Dockerfile for Holodeck-SMP (deterministic jar selection, safer caching, non-root runtime)
#
# Usage:
#  docker build --build-arg APP_MODULE=smp-server-app -t holodeck-smp:latest .
# If your main module has a different artifactId/module folder, set APP_MODULE accordingly.

# Build stage
FROM maven:3.9.5-eclipse-temurin-17 AS build
ARG APP_MODULE=smp-server-app
WORKDIR /workspace

# Copy root pom first to enable dependency layer caching
COPY pom.xml ./

# Copy module pom files (will match existing modules in the repo) to help mvn go-offline.
# Note: this copies all module pom.xml files matched by the glob; keep it to accelerate dependency resolution.
COPY */pom.xml ./

# Pre-download dependencies to leverage Docker layer cache
RUN mvn -B -e dependency:go-offline

# Copy full project
COPY . .

# Try to build the application module first (faster); fall back to full reactor build.
RUN mvn -B -DskipTests -pl :${APP_MODULE} -am package || mvn -B -DskipTests package

# Prefer deterministic artifact from the application module; fall back to scanning target folders.
RUN set -eux; \
    jar=""; \
    if [ -d "${APP_MODULE}/target" ]; then \
        jar="$(find "${APP_MODULE}/target" -maxdepth 1 -type f -name '*.jar' ! -name '*-sources.jar' ! -name '*-javadoc.jar' ! -name '*-original.jar' | head -n1 || true)"; \
    fi; \
    if [ -z "$jar" ]; then \
        jar="$(find . -type f -path '*/target/*.jar' ! -name '*-sources.jar' ! -name '*-javadoc.jar' ! -name '*-original.jar' | head -n1 || true)"; \
    fi; \
    if [ -z "$jar" ]; then \
        echo 'ERROR: no built jar found under */target' >&2; exit 1; \
    fi; \
    mkdir -p /workspace/dist; \
    cp "$jar" /workspace/dist/app.jar; \
    echo "Selected jar: $jar";

# Runtime stage
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app

# Create unprivileged user
RUN groupadd -r app && useradd -r -g app -d /app -s /sbin/nologin app \
    && mkdir -p /app && chown app:app /app

# Copy application jar and set ownership
COPY --from=build /workspace/dist/app.jar /app/app.jar
RUN chown app:app /app/app.jar

# Allow runtime customization of JVM options and server port
ENV JAVA_OPTS="-Xms256m -Xmx512m" \
    SERVER_PORT=8080

USER app
EXPOSE 8080

ENTRYPOINT ["sh","-c","exec java $JAVA_OPTS -jar /app/app.jar"] 