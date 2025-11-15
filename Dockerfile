# Multi-stage Dockerfile for Holodeck-SMP
# Builds a multi-module Maven project and packages the runnable JAR into a minimal runtime image.
#
# Usage:
#  docker build -t holodeck-smp:latest .
#  docker build --build-arg APP_MODULE=smp-server-app -t holodeck-smp:latest .

FROM maven:3.9.5-eclipse-temurin-17 AS build
ARG APP_MODULE=smp-server-app
WORKDIR /workspace

# Copy entire project structure early to avoid breaking reactor resolution
COPY . .

# Pre-download dependencies to leverage Docker layer cache
# Run offline mode to pre-fetch all dependencies for faster builds
RUN mvn -B -e dependency:go-offline -DskipTests

# Build the application module with all dependencies pre-cached
# This builds the module and its upstream dependencies
RUN mvn -B -e -DskipTests -pl :${APP_MODULE} -am package

# Locate and copy the runnable JAR (exclude source/javadoc jars)
RUN set -eux; \
    jar="$(find . -type f -path '*/target/*.jar' ! -name '*-sources.jar' ! -name '*-javadoc.jar' ! -name '*-original.jar' | head -n1)"; \
    if [ -z "$jar" ]; then \
        echo 'ERROR: no built jar found under */target' >&2; \
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

ENTRYPOINT ["sh","-c","exec java $JAVA_OPTS -jar /app/app.jar"]