# Pixez-s (Headless Server)

`Pixez-s` 是 `Pixez-cs` 架构中的无头服务端（Headless Server）。可在 Linux 服务器、家庭 NAS、软路由或 Docker 容器中 7×24 小时独立运行。

## 🌟 核心特性

1. **Pixiv 认证托管与自动刷新**：由服务端统一管理 Refresh Token，定时刷新 Access Token，避免多设备客户端频繁重新登录。
2. **阻断绕过与上游代理**：服务端统一配置外部 HTTP 代理（`PIXEZ_PROXY`），客户端无需自行配置繁琐的翻墙或 DoH 规则。
3. **媒体反代与磁盘缓存**：自动附加 Pixiv 防盗链 Referer，首次加载自动缓存原图/缩略图至服务端本地磁盘，二次访问毫秒级直出。
4. **离线元数据归档（时光机）**：伴随下载自动归档完整的标签列表（Tags）、作品简介（Caption）、画师信息与系列章节信息。
5. **删作自动路由回退（Fallback Mirror）**：当原作者在 Pixiv 上删作（上游返回 404/被删除）时，服务端自动无缝回退到本地归档库，按标准格式返回本地镜像与本地图片流。
6. **后台下载引擎**：多线程下载队列，支持 WebSocket 实时进度广播。

---

## 🚀 快速启动

### 方式 1：直接运行 (Dart 3.x)
```bash
cd packages/pixez-s
dart pub get
dart run bin/server.dart
```

### 方式 2：Docker 运行
```bash
docker compose up -d
```

---

## 📡 API 路由概览

- **健康检查**：`GET /health`
- **账号认证**：
  - `POST /api/v1/auth/token` (提交 refresh_token)
  - `GET /api/v1/auth/accounts` (获取账号列表)
  - `POST /api/v1/auth/switch` (切换活动账号)
- **Pixiv 核心业务**：
  - `GET /api/v1/pixiv/illust/{id}` (获取插画详情，**支持原作者删作后自动回退本地镜像**)
  - `GET /api/v1/pixiv/ranking` (排行榜)
  - `GET /api/v1/pixiv/recommended` (推荐流)
  - `GET /api/v1/pixiv/search` (插画搜索)
  - `GET /api/v1/pixiv/ugoira/{id}/metadata` (动图元数据)
  - `GET /api/v1/pixiv/user/{id}` (画师详情)
- **本地归档库**：
  - `GET /api/v1/archives` (按标签/关键词检索本地离线归档)
  - `GET /api/v1/archives/{id}` (查看单篇归档详情)
- **图片与媒体流**：
  - `GET /api/v1/media/image?url=...` (防盗链缓存反代)
  - `GET /api/v1/media/archive/{work_type}/{work_id}/{filename}` (本地镜像静态媒体流)
- **下载任务**：
  - `POST /api/v1/tasks` (提交下载并触发自动归档)
  - `GET /api/v1/tasks` (查看任务队列)
  - `WS /api/v1/ws` (WebSocket 实时事件与下载进度推送)
