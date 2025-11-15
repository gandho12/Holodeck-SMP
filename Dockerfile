# Multi-stage Dockerfile for Holodeck-SMP (deterministic jar selection, safer caching, non-root runtime)
#
# Usage:
#  docker build --build-arg APP_MODULE=smp-server-app --build-arg MAVEN_SETTINGS=./settings.xml -t holodeck-smp:latest .

FROM maven:3.9.5-eclipse-temurin-17 AS build
ARG APP_MODULE=smp-server-app
ARG MAVEN_SETTINGS=
WORKDIR /workspace

# Copy root pom first to enable dependency layer caching
COPY pom.xml ./

# Copy module poms explicitly to preserve layout and avoid overwriting similarly-named files.
# Include all child modules referenced in the parent pom (add more as needed).
COPY generic-server/pom.xml generic-server/pom.xml
COPY peppol-smp/pom.xml peppol-smp/pom.xml
COPY oasis-smp2/pom.xml oasis-smp2/pom.xml
COPY mgmt-api/pom.xml mgmt-api/pom.xml
COPY distr/pom.xml distr/pom.xml

# Optionally provide a custom settings.xml (for private repos/mirrors)
# Pass --build-arg MAVEN_SETTINGS=./path/to/settings.xml to include it
RUN if [ -n "$MAVEN_SETTINGS" ]; then \
      mkdir -p /root/.m2 && cp $MAVEN_SETTINGS /root/.m2/settings.xml ; \
    fi

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

FROM eclipse-temurin:17-jre-jammy
WORKDIR /app

# Create unprivileged user
RUN groupadd -r app && useradd -r -g app -d /app -s /sbin/nologin app \
    && mkdir -p /app && chown app:app /app

# Copy application jar and set ownership
COPY --from=build /workspace/dist/app.jar /app/app.jar
RUN chown app:app /app/app.jar

ENV JAVA_OPTS="-Xms256m -Xmx512m" \
    SERVER_PORT=8080

USER app
EXPOSE 8080

ENTRYPOINT ["sh","-c","exec java $JAVA_OPTS -jar /app/app.jar"]