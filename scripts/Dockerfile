FROM swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/node:22-alpine AS web-builder
WORKDIR /src
COPY webdesktop/package.json webdesktop/package-lock.json* webdesktop/pnpm-lock.yaml* webdesktop/yarn.lock* webdesktop/.npmrc* ./webdesktop/
RUN cd webdesktop && npm i --no-audit --no-fund
COPY webdesktop ./webdesktop
RUN cd webdesktop && npm run build

FROM swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/rust:1.83 AS server-builder
RUN apt-get update && apt-get install -y --no-install-recommends musl-tools pkg-config ca-certificates && rm -rf /var/lib/apt/lists/* \
  && rustup target add x86_64-unknown-linux-musl
WORKDIR /src/server
COPY server/Cargo.toml server/Cargo.lock* ./
COPY server/src ./src
RUN cargo build --release --target x86_64-unknown-linux-musl

FROM swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/alpine:3.19
RUN apk add --no-cache postgresql16 postgresql16-client openssl su-exec
ENV PGDATA=/var/lib/postgresql/data
ENV DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/pnas
ENV JWT_SECRET=dev-secret
ENV SYSTEM_DIR=/srv/system
ENV STATIC_DIR=/srv/system/www
ENV FS_BASE_DIR=/srv/nas
ENV POSTGRES_PASSWORD=postgres
WORKDIR /srv

COPY --from=server-builder /src/server/target/x86_64-unknown-linux-musl/release/pnas-server /usr/local/bin/pnas-server
COPY --from=web-builder /src/webdesktop/dist /usr/share/pnas/www

RUN mkdir -p /var/lib/postgresql/data /var/run/postgresql "$SYSTEM_DIR" && chown -R postgres:postgres /var/lib/postgresql /var/run/postgresql

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8000
CMD ["/usr/local/bin/entrypoint.sh"]
