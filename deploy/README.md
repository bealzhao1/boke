# 通过 kubeconfig 部署到 k3s

本方案用 `kubectl` + kubeconfig 把博客部署到 k3s 集群，取代之前的 SSH 方式。
流程：**GitHub Actions 构建镜像 → 推送到 ghcr.io → 用 kubeconfig 连集群 → kubectl apply 部署**。

## 一、GitHub 侧要配的东西

到仓库 **Settings → Secrets and variables → Actions**：

### Secrets（敏感，加密存储）

| 名称 | 值 |
|------|-----|
| `KUBECONFIG` | 你 k3s 集群的 kubeconfig 完整内容（见下方「怎么拿到 kubeconfig」） |
| `GHCR_PAT` | 一个 Personal Access Token，勾选 `read:packages`（用于集群拉取私有镜像，**必须长期有效**） |

> 为什么用 PAT 而不是 `GITHUB_TOKEN`：`GITHUB_TOKEN` 每次运行结束就失效，集群节点之后重启/扩容时拉镜像会 401，所以用长期 PAT。

### Variables（非敏感）

| 名称 | 值 | 说明 |
|------|-----|------|
| `BASE_URL` | `https://blog.bealzhao.com/blog/` | 编译时注入 hugo 的 baseURL，**必须带 `/blog/` 子路径**，见下方说明 |
| `BLOG_HOST` | `blog.bealzhao.com` | Ingress 的域名（可选，不配则用 ingress.yaml 里写死的值） |

### ⚠️ 关于 `/blog` 子路径（重要）

站点挂在 `/blog` 下，靠 Ingress 注解把前缀剥掉后再转发给 Pod：

```
浏览器请求  https://blog.bealzhao.com/blog/css/style.css
   ↓ 匹配 /blog(/|$)(.*)，rewrite-target: /$2
转发给 Pod  /css/style.css
   ↓
Nginx 返回  /usr/share/nginx/html/css/style.css
```

**`BASE_URL` 必须带上 `/blog/`**，否则 Hugo 生成的链接是 `/css/style.css`，
浏览器会去请求 `https://blog.bealzhao.com/css/style.css`，Ingress 无此规则 → 404。

访问地址：https://blog.bealzhao.com/blog/

## 二、怎么拿到 kubeconfig（在 k3s 服务器上）

k3s 的 kubeconfig 在 `/etc/rancher/k3s/k3s.yaml`：

```bash
# 1. 取出并复制内容
sudo cat /etc/rancher/k3s/k3s.yaml
```

**关键：必须改两个地方，否则 GitHub Actions 连不上：**

1. 把 `server: https://127.0.0.1:6443` 改成**公网可达地址**（服务器公网 IP 或域名）：
   ```yaml
   server: https://<你的公网IP>:6443
   ```

2. **证书 SAN 问题**：k3s 默认生成的 API server 证书只认节点 IP/主机名。
   如果 GitHub Actions 要从公网访问，安装 k3s 时必须加 `--tls-san`：
   ```bash
   curl -sfL https://get.k3s.io | sh -s - --tls-san <你的公网IP或域名>
   ```
   如果集群已经装好、没加过 `--tls-san`，最简单是重装（数据少的话）：
   ```bash
   sudo systemctl stop k3s
   curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --tls-san <你的公网IP或域名>" sh -
   ```

   最后把完整的 kubeconfig 内容整个粘到 `KUBECONFIG` secret 里。

3. **放行 6443 端口**：安全组/防火墙要允许 GitHub Actions 的出口 IP 访问 6443。
   更安全的做法是用内网穿透或只对特定 IP 开放，避免裸奔暴露 API server。

## 三、集群里要准备的东西

### 1. 安装 nginx ingress controller

k3s 默认的 ingress 是 Traefik，本项目用的 `ingressClassName: nginx`，需要额外装 ingress-nginx：

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml
```

### 2. 域名解析

把 `blog.bealzhao.com`（或你的域名）解析到 k3s 节点 IP。

## 四、触发部署

推代码到 `main` 分支即可自动触发，也可以在 Actions 页面手动点 **Run workflow**。

```bash
cd /Users/zhaodeman/boke
git add -A
git commit -m "deploy: 改为 kubeconfig + kubectl 部署到 k3s"
git push origin main
```

## 五、常见问题

| 现象 | 原因 | 解决 |
|------|------|------|
| `Unable to connect to the server: x509` | 证书 SAN 不含公网地址 | 装 k3s 时加 `--tls-san` |
| `ImagePullBackOff` / `401` | 拉私有镜像没凭证或凭证过期 | 检查 `ghcr-secret`、`GHCR_PAT` 权限 |
| `connection refused` | 6443 端口没放行 | 安全组放行 6443 |
| Ingress 不生效 | ingress controller 没装或 class 不匹配 | 确认装的是 nginx controller |
