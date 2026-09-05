# boke 博客部署：bealzhao.cn/blog

**目标**：`https://bealzhao.cn/` 根路径是 **shiling 应用**（由 nginx Pod 反代），保留不动；
boke 博客通过 `https://bealzhao.cn/blog/` 访问，由**同一个 nginx Pod** 增加静态 location 提供服务。

**服务器现状（k3s）**：`bealzhao.cn/` → Traefik → Service `nginx:80` → nginx Pod（官方 `nginx:alpine`）。
nginx Pod 只挂了一个 ConfigMap `nginx-conf`（server 配置），根路径用 `proxy_pass` 反代到
`shiling.shiling.svc.cluster.local:80`，本身**不托管静态文件**。

因此让 boke 走 `/blog` 需要做两件事：给 nginx 配置加 `/blog` 静态 location + 给 Pod 挂一块
**hostPath 卷**作为 boke 文件落点（CI 同步目标）。

## 一、流量路径（改造后）

```
浏览器 https://bealzhao.cn/
  ├── /blog/*   → nginx location ^~ /blog/（静态）
  │                → root /usr/share/nginx/html → /usr/share/nginx/html/blog/xxx
  │                → hostPath 卷 /data/nginx-blog（宿主机目录）   ← boke 文件
  └── /*         → location /（反代，保留）→ shiling 服务
```

## 二、服务器侧一次性改动（k3s 节点上执行）

### 1. 更新 nginx 配置（新增 /blog 静态 location，保留反代）

```bash
cat > /tmp/default.conf <<'EOF'
server {
    listen 80;
    server_name _;

    # ===== boke 博客静态站点：/blog/xxx → /usr/share/nginx/html/blog/xxx =====
    location = /blog {
        return 301 /blog/;
    }
    location ^~ /blog/ {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri $uri/ =404;
    }

    # ===== 根路径：反代到 shiling（保留原逻辑） =====
    location / {
        proxy_pass http://shiling.shiling.svc.cluster.local:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EOF

kubectl create configmap nginx-conf --from-file=default.conf=/tmp/default.conf -o yaml --dry-run=client | kubectl apply -f -
```

### 2. 节点上建目录 + 给 Deployment 挂 hostPath 卷

```bash
mkdir -p /data/nginx-blog && chmod 755 /data/nginx-blog

kubectl patch deploy nginx --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"boke-site","mountPath":"/usr/share/nginx/html/blog"}},
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"boke-site","hostPath":{"path":"/data/nginx-blog","type":"DirectoryOrCreate"}}}
]'

kubectl rollout status deploy/nginx
```

> Pod 重建时 ConfigMap 与卷一起生效，无需单独 reload。

## 三、GitHub 侧要配的东西

仓库 **Settings → Secrets and variables → Actions**：

### Secrets（敏感）

| 名称 | 值 |
|------|-----|
| `SSH_HOST` | k3s 节点服务器 IP 或域名 |
| `SSH_USER` | SSH 用户名（对 `/data/nginx-blog` 有写权限，root 即可） |
| `SSH_KEY` | SSH 私钥完整内容 |

### Variables（非敏感）

| 名称 | 值 | 说明 |
|------|-----|------|
| `BASE_URL` | `https://bealzhao.cn/blog/` | **必须带 `/blog/`**，否则资源链接会落到根路径反代上 404 |
| `SERVER_WEBROOT` | `/data/nginx-blog` | nginx Pod hostPath 卷的宿主机目录（CI rsync 目标） |

## 四、触发部署

```bash
cd boke
git add -A
git commit -m "chore: 更新博客内容"
git push origin main
```

或仓库 Actions 页面手动 **Run workflow**。rsync 成功后访问 `https://bealzhao.cn/blog/`。

## 五、常见问题

| 现象 | 原因 | 解决 |
|------|------|------|
| `缺少 secret: SSH_HOST/SSH_USER/SSH_KEY` | 未配置 secret | GitHub Settings → Secrets and variables → Actions 配置 |
| `缺少 variable: SERVER_WEBROOT` | 未配置 variable | Variables 填 `/data/nginx-blog` |
| `Permission denied (publickey)` | 私钥不匹配 | 检查 `SSH_KEY` 与服务器 `authorized_keys` |
| rsync 报 `change_dir Permission denied` | SSH 用户对 `/data/nginx-blog` 无写权限 | `chown`/`chmod` 该目录 |
| 同步成功但 `/blog/` 404 | ① location 未加 ② 卷没挂 ③ 同步目录不对 | 检查第二节的 ConfigMap 与 patch 是否已执行 |
| 页面出现但 CSS/图片 404 | `BASE_URL` 没带 `/blog/` | 配成 `https://bealzhao.cn/blog/` 重跑 |
| 根路径站点被影响？ | —— | 不会：反代 location 保留，`/blog` 为独立 location，rsync 只写 `/data/nginx-blog` |
