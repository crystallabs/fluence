FROM crystallang/crystal:1.21.0-alpine AS build
WORKDIR /app
COPY shard.yml shard.lock ./
RUN shards install --production
COPY . .
RUN crystal build --release --static -o bin/fluence src/fluence.cr

FROM alpine:3.22
# git is required at runtime: page edits are committed to a repository in data/.
# The committer identity is used for `git commit`; page authors are recorded
# via --author on each commit.
RUN apk add --no-cache git \
 && git config --system user.name "Fluence Wiki" \
 && git config --system user.email "fluence@localhost" \
 && git config --system init.defaultBranch master
WORKDIR /app
COPY --from=build /app/bin/fluence ./fluence
COPY public ./public
# Wiki content (data/) and metadata (meta/) live under the working directory
# by default; mount volumes here to persist them.
VOLUME ["/app/data", "/app/meta"]
EXPOSE 3000
CMD ["./fluence"]
