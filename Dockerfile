# syntax=docker/dockerfile:1
###############################################################################
# Build-time knobs                                                            #
###############################################################################
ARG TB_VERSION=4.0.2     # 3.9.0 for TB 3.x | 4.0.2 for TB 4.x (default)
ARG TB_EDITION=ce        # "ce"  or "pe"

###############################################################################
# 🔨 1. Builder for TB 3.x (server-side JAR)                                  #
###############################################################################
FROM maven:3.9-eclipse-temurin-17 AS build-3x

# ── Essentials: git + CA bundle ──────────────────────────────────────────────
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Node & Yarn for widget sub-module
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
 && apt-get install -y nodejs \
 && npm install -g yarn@1.22

WORKDIR /opt/ext
COPY . .
RUN mvn -B clean install -DskipTests

###############################################################################
# 🔨 2. Builder for TB 4.x (widget bundle)                                    #
###############################################################################
FROM node:18-bullseye-slim AS build-4x

# ── Essentials: git + CA bundle ──────────────────────────────────────────────
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/ext
COPY . .
RUN yarn install --frozen-lockfile \
 && yarn build                              # bundle -> target/generated-resources/

###############################################################################
# 📦 3a. Runtime image for TB 3.x                                             #
###############################################################################
FROM thingsboard/tb-postgres:${TB_VERSION} AS tb3x

ARG EXT_DIR=/usr/share/thingsboard/extensions
COPY --from=build-3x --chown=thingsboard:thingsboard \
     /opt/ext/widgets/target/*.jar ${EXT_DIR}/
RUN chmod 555 ${EXT_DIR}/*      # chmod is fine; file owner already correct

###############################################################################
# 📦 3b. Runtime image for TB 4.x (default)                                   #
###############################################################################
FROM thingsboard/tb-postgres:${TB_VERSION} AS tb4x

ARG STATIC_DIR=/usr/share/thingsboard/static/widgets
COPY --from=build-4x --chown=thingsboard:thingsboard \
     /opt/ext/target/generated-resources/*.js ${STATIC_DIR}/
# No chown needed anymore; permissions already right

###############################################################################
# 📦 4. Default final stage (TB 4.x)                                          #
###############################################################################
FROM tb4x



# ThingsBoard 4.0.2 (default)
# docker build -t myext:4.0.2 --build-arg TB_VERSION=4.0.2 .
# docker run -d --name tb402 -p 80:8080 -e TB_QUEUE_TYPE=in-memory myext:4.0.2

# ThingsBoard 3.9.0
# docker docker build -t myext:3.9.0 --build-arg TB_VERSION=3.9.0 --target=tb3x .
# docker run -d --name tb390 -p 80:8080 -e TB_QUEUE_TYPE=in-memory myext:3.9.0
