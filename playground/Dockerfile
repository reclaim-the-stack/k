FROM ubuntu:noble-20240904.1

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update
RUN apt-get install apt-transport-https ca-certificates gnupg git wget curl lsb-release unzip -y

# Postgres client (https://www.postgresql.org/download/linux/ubuntu/)
RUN apt-get install postgresql-client -y

# Redis client
RUN curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
RUN apt-get update
RUN apt-get install redis -y

# ClickHouse client
RUN curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | tee /etc/apt/sources.list.d/clickhouse.list
RUN apt-get update
RUN apt-get install clickhouse-client -y

# etcd client
RUN wget https://github.com/etcd-io/etcd/releases/download/v3.5.5/etcd-v3.5.5-linux-amd64.tar.gz && \
  tar xvf etcd-v3.5.5-linux-amd64.tar.gz && \
  cd etcd-v3.5.5-linux-amd64 && \
  mv etcd etcdctl etcdutl /usr/local/bin && \
  rm -rf etcd-v3.5.5-linux-amd64*

# AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
  unzip awscliv2.zip && \
  ./aws/install && \
  rm -rf awscliv2.zip aws

RUN apt-get install -y \
  dnsutils \
  fdisk \
  fio \
  fping \
  iputils-ping \
  iproute2 \
  neovim \
  nodejs \
  default-jre-headless \
  ruby-full \
  traceroute \
  wrk \
  zstd
