FROM scratch

ARG IMAGE_NAME="controlplane/kubernetes-json-schema"
ARG SCHEMA_SOURCE="https://github.com/instrumenta/kubernetes-json-schema/"
ARG SOURCE="https://github.com/controlplaneio/kubernetes-json-schema-container/"
ARG CI_LINK="N/A"
ARG SHA="N/A"
ARG DATETIME

LABEL org.opencontainers.image.name=${IMAGE_NAME} \
      org.opencontainers.image.description="X" \
      org.opencontainers.image.created=${DATETIME} \
      org.opencontainers.image.source=${SOURCE} \
      org.opencontainers.image.revision=${SHA} \
      org.opencontainers.image.ci_link=${CI_LINK} \
      org.opencontainers.image.schema_source=${SCHEMA_SOURCE}

COPY . /
