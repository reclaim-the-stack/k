# Note: Only LTS Ubuntu releases are supported by Postgresql Global Development Group (PGDG)
FROM ubuntu:noble-20251001

ARG TARGETOS
ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Base tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      apt-transport-https ca-certificates curl gnupg git wget lsb-release unzip \
      dnsutils fdisk fio fping iputils-ping iproute2 neovim nodejs \
      default-jre-headless ruby-full traceroute wrk zstd && \
    rm -rf /var/lib/apt/lists/*

# --- PostgreSQL clients 16/17/18 via PGDG (manual repo config on noble) ---
# Using your working approach: store ASCII key and reference it directly
ARG PG_VERSIONS="16 17 18"
RUN set -eux; \
    install -d /usr/share/postgresql-common/pgdg && \
    curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
    . /etc/os-release && \
    sh -c "echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main' > /etc/apt/sources.list.d/pgdg.list" && \
    apt-get update; \
    for v in ${PG_VERSIONS}; do \
      apt-get install -y --no-install-recommends "postgresql-client-${v}" && \
      ln -sf "/usr/lib/postgresql/${v}/bin/psql" "/usr/local/bin/psql${v}" && \
      ln -sf "/usr/lib/postgresql/${v}/bin/pg_dump" "/usr/local/bin/pg_dump${v}" && \
      ln -sf "/usr/lib/postgresql/${v}/bin/pg_dumpall" "/usr/local/bin/pg_dumpall${v}" && \
      ln -sf "/usr/lib/postgresql/${v}/bin/pg_restore" "/usr/local/bin/pg_restore${v}"; \
    done; \
    rm -rf /var/lib/apt/lists/*

# --- Redis client ---
RUN curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/redis.list && \
    apt-get update && apt-get install -y --no-install-recommends redis && \
    rm -rf /var/lib/apt/lists/*

# --- ClickHouse client ---
RUN set -eux; \
    install -d /usr/share/keyrings; \
    curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg arch=${TARGETARCH}] https://packages.clickhouse.com/deb stable main" \
      > /etc/apt/sources.list.d/clickhouse.list; \
    apt-get update && apt-get install -y --no-install-recommends clickhouse-client && \
    rm -rf /var/lib/apt/lists/*

# --- etcd / etcdctl / etcdutl (multi-arch) ---
ARG ETCD_VERSION=3.5.24
RUN set -eux; \
    url="https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz"; \
    curl -fsSL "$url" -o /tmp/etcd.tgz; \
    tar -xzf /tmp/etcd.tgz -C /tmp; \
    dir="/tmp/etcd-v${ETCD_VERSION}-linux-${TARGETARCH}"; \
    install -m 0755 "$dir/etcd" "$dir/etcdctl" "$dir/etcdutl" /usr/local/bin/; \
    rm -rf /tmp/etcd.tgz "$dir"

# --- AWS CLI v2 (multi-arch) ---
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) AWS_ARCH=x86_64 ;; \
      arm64) AWS_ARCH=aarch64 ;; \
      *) echo "Unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip; \
    unzip /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscliv2.zip
