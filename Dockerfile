# ============ 构建 Hugo 静态站点 ============
# 该镜像只负责生成静态文件，不再内置运行环境：
# 博客由服务器上已有的 nginx 托管，构建产物通过 docker run 导出后同步到 nginx webroot。
#
# 本地用法：
#   docker build -t boke-builder --build-arg BASE_URL=https://blog.example.com/ .
#   docker run --rm -v "$PWD/public:/out" boke-builder cp -r /src/public/. /out/
# 构建产物输出目录：/src/public
FROM ubuntu:24.04

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
