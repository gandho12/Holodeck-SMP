# Multi-stage Dockerfile for Holodeck-SMP
# Builds a multi-module Maven project and packages the runnable JAR into a minimal runtime image.
#
# Usage:
#  docker build -t holodeck-smp:latest .

FROM maven:3.9.5-eclipse-temurin-17 AS build
ARG APP_MODULE=smp-server-app
WORKDIR /workspace

# Copy entire project structure
COPY . .

# Build the application module and all upstream dependencies
# Note: dependency:go-offline is skipped because internal dependencies
# (e.g., generic-utils:1.1.0) are only available via custom/private repositories.
# Maven will resolve dependencies during the build phase.
RUN mvn -B -e -DskipTests -pl :${APP_MODULE} -am clean package

# Locate and copy the runnable JAR (exclude source/javadoc jars)
RUN set -eux; \
    jar="$(find . -type f -path '*/target/*.jar' ! -name '*-sources.jar' ! -name '*-javadoc.jar' ! -name '*-original.jar' -print | head -n1)"; \
    if [ -z "$jar" ]; then \
        echo 'ERROR: no built jar found under */target' >&2; \
        find . -type f -path '*/target/*.jar' -print; \
        exit 1; \
    fi; \
    mkdir -p /workspace/dist; \
    cp "$jar" /workspace/dist/app.jar; \
    echo "Selected jar: $jar";

# Runtime stage
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app

# Create non-root user for security
RUN groupadd -r app && useradd -r -g app -d /app -s /sbin/nologin app && \
    mkdir -p /app && chown app:app /app

# Copy application jar
COPY --from=build /workspace/dist/app.jar /app/app.jar
RUN chown app:app /app/app.jar

# Runtime configuration
ENV JAVA_OPTS="-Xms256m -Xmx512m" \
    SERVER_PORT=8080

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD java -jar /app/app.jar --help 2>/dev/null || exit 1

ENTRYPOINT ["sh","-c","exec java $JAVA_OPTS -jar /app/app.jar"]