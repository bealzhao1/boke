---
title: "分布式限流"
date: 2026-09-04
draft: false
desceription: "分布式限流"
tags: ["微服务"]
categories: ["微服务"]
---


## 限流算法
### 令牌桶算法

在一定时间内，向桶里面放入 **n** 个令牌，当请求到来时，我们从桶里面取出一个令牌；
如果桶里面没有令牌，那么请求被拒绝。
允许流量的突发，例如在 **1s** 之内，前 **0 ~ 998ms** 没有请求，第 **999ms** 突然来了大量的请求，那么这段时间的请求是被允许的。

```
本地首推官方令牌桶库：golang.org/x/time/rate
参考文档：https://pkg.go.dev/golang.org/x/time/rate
```

使用示例：
```go

```


```bash
hugo server -D   # 本地预览
hugo new posts/新文章.md   # 新建文章
hugo             # 构建到 public/
```
