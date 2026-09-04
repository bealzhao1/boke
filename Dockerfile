# ============ 阶段一：构建 Hugo 静态站点 ============
FROM ubuntu:24.04 AS builder

ARG HUGO_VERSION=0.165.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q -O /tmp/hugo.deb \
      "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.deb" \
    && dpkg -i /tmp/hugo.deb \
    && rm -f /tmp/hugo.deb

WORKDIR /src
COPY . .

# 可通过 --build-arg BASE_URL=https://blog.example.com/ 覆盖 hugo.toml 中的 baseURL
# 未传该参数时使用 hugo.toml 里配置的 baseURL
ARG BASE_URL=""
RUN hugo --gc --minify ${BASE_URL:+--baseURL "$BASE_URL"}

# ============ 阶段二：用 Nginx 托管静态文件 ============
FROM nginx:1.27-alpine

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
