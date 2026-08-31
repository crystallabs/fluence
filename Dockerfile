FROM crystallang/crystal:1.21.0-alpine AS build
WORKDIR /app
COPY shard.yml shard.lock ./
RUN shards install --production
COPY . .
RUN crystal build --release --static -o bin/fluence src/fluence.cr

FROM alpine:3.22
# git is required at runtime: wiki content lives in a git repository in
# data/ (bare by default). Author and committer identities are passed via
# environment on each commit, so no git configuration is needed.
RUN apk add --no-cache git
WORKDIR /app
COPY --from=build /app/bin/fluence ./fluence
COPY public ./public
# Wiki content (data/, a git repository) and metadata (meta/) live under
# the working directory by default; mount volumes here to persist them.
VOLUME ["/app/data", "/app/meta"]
EXPOSE 3000
CMD ["./fluence"]
