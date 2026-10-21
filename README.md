# Clouds-remain

基于 **Hexo 7.3.0** 与 **ShokaX 0.5.4** 的个人博客，使用 GitHub Actions 构建并发布到 GitHub Pages。

线上地址：<https://clouds-remain.github.io/>

## 本地环境

本项目在这台 Windows 电脑上使用以下环境完成搭建：

| 工具 | 版本 | 安装位置 |
| --- | --- | --- |
| Node.js | 24.20.0 | `D:\Users\49161\AppData\Local\Programs\nodejs` |
| npm | 11.19.0 | 随 Node.js 提供 |
| Git | 2.55.0 | `D:\Users\49161\AppData\Local\Programs\PortableGit` |

两者的可执行目录已加入当前用户的 `PATH`。如果现有终端里找不到 `node` 或 `git`，重新打开一个终端即可。

## 常用命令

```powershell
npm run server   # 本地预览：http://localhost:4000
npm run build    # 生成 public/，并建立 Pagefind 搜索索引
npm run clean    # 清理缓存与 public/
npx hexo new post "文章标题"
```

> `npm run build` 等价于 `hexo generate && pagefind --site public`。不要只运行 `hexo generate` 后直接部署，否则搜索索引会缺失。

## 一键发布

双击仓库根目录的 `publish.cmd`，会打开菜单：

1. 从列表选择文章发布
2. 发布全部改动文章
3. 新建文章（创建后打开 Obsidian / 记事本）
4. 设置/更换文章封面并发布
5. 只构建预览
6. 退出

也可以直接运行：

```powershell
# 从文章列表中选择
.\tools\publish.ps1 -Pick

# 发布所有改动文章
.\tools\publish.ps1 -All

# 发布指定文章
.\tools\publish.ps1 -File "文章标题.md"

# 给指定文章设置封面并发布
.\tools\publish.ps1 -File "文章标题.md" -CoverImage "D:\图片\cover.jpg"

# 只检查、构建，不提交
.\tools\publish.ps1 -DryRun

# 新建文章
.\tools\publish.ps1 -Title "新文章标题"
```

## 自定义文章封面

每篇文章的卡片封面由 front matter 的 `cover` 决定：

```yaml
---
title: 文章标题
cover: images/posts/文章标题-cover.jpg
---
```

图片放在 `source/images/posts/`。注意：

- `cover` 路径**不要**以 `/` 开头
- 推荐 16:9 或 3:2，宽度 1200px 以上
- 支持 jpg / png / webp

也可以在 Obsidian 里只做两件事：

1. 把封面图片放到 `source/images/posts/`
2. 在文章 front matter 加一行 `cover: images/posts/xxx.jpg`

发布脚本会自动检测并暂存这个封面图片。

不想手动找路径时，双击 `publish.cmd` 选择 **4. 设置/更换文章封面并发布**，脚本会列出文章、弹出文件选择框，自动复制图片、写入 `cover`，然后继续发布。

脚本包含这些 fallback：

- Node/npm/Git 不在 PATH 时，自动尝试已知安装目录
- `npm run build` 失败时，回退到 `hexo generate + pagefind`
- `git pull` 失败时，回退到 `ghproxy.net` 镜像拉取
- `git push` 失败时自动重试；仍失败则保留本地提交，并在 `.publish/rescue/` 生成 patch 和 bundle
- 构建失败不会提交，避免把坏版本推上线
- 只提交选中的文章和文章引用的本地图片，不会误提交 `.obsidian`
- 发布锁防止同时运行两个发布进程
- 完整日志在 `.publish/logs/`

## 配置地图

| 文件 | 作用 |
| --- | --- |
| `_config.yml` | 站点名称、副标题、作者、URL、语言、永久链接、主题入口 |
| `_config.shokax.yml` | ShokaX 主题配置；这是主要需要修改的文件 |
| `source/_data/images.yml` | 文章默认封面池（至少 6 张，否则 ShokaX 会拒绝生成） |
| `source/_data/images_index.yml` | 首页封面池 |
| `source/_data/assets/` | 头像、favicon、友链图片等静态素材，发布到 `/assets/` |
| `source/images/covers/` | 本地生成的 6 张封面图 |
| `scripts/site.js` | 浏览器标题与首页标题的小修补，不属于主题包 |
| `.github/workflows/pages.yml` | GitHub Pages 构建与部署工作流 |

主题通过 npm 安装，位于 `node_modules/hexo-theme-shokax/`，**不要直接修改该目录**，升级时会被覆盖。

## 当前已启用

- 中文界面、深色模式、20:00–07:00 自动切换
- 首页大标题 + 副标题「我的灵魂腐烂在那个夏日的一场梦境」
- 导航：首页 / 文章（归档、分类、标签）/ 友链 / 关于
- Pagefind 本地全文搜索（构建时自动索引）
- 关于页 `/about/`、友链页 `/friends/`
- 文章字数、阅读时长、站点总字数
- 中国大陆可访问的 CDN 与系统字体，不加载 Google Fonts
- **评论：Twikoo 已启用（Netlify + MongoDB Atlas）**
- **音乐播放器：保持关闭**
- **鼠标烟花：保持关闭**

## 后续修改

### 换头像或封面

- 头像：替换 `source/_data/assets/avatar.jpg` 后重新构建
- 封面：替换 `source/images/covers/cover-1.jpg` 到 `cover-6.jpg`，并在 `source/_data/images.yml`、`images_index.yml` 中保持 6 条路径
- 首页背景：替换 `source/images/background.jpg`
- 首页固定封面：修改 `_config.shokax.yml` 的 `homeConfig.fixedCover`

### 评论维护

当前使用 Twikoo，后端部署在 Netlify，数据库为 MongoDB Atlas：

```yaml
twikoo:
  enable: true
  mode: vercel
  envId: "https://clouds-remain-twikoo.netlify.app/.netlify/functions/twikoo"
```

- Netlify 项目：`clouds-remain-twikoo`
- 环境变量：`MONGODB_URI`（Netlify 环境变量中配置，仓库里不保存连接串）
- 关闭评论：把 `twikoo.enable` 改为 `false`
- 更换评论后端：只改 `envId`，地址必须是完整的 Twikoo 函数地址

### 开启音乐播放器

1. 在 `_config.shokax.yml` 把 `modules.player` 改为 `true`
2. 在 `audio` 中填入歌单，例如：

```yaml
audio:
  - title: 我的歌单
    list:
      - https://music.163.com/#/playlist?id=你的歌单ID
```

播放器依赖 Meting API（`playerAPI`），默认使用 `https://api.injahow.cn`；如果接口失效，需要换成可用的 Meting 服务。

### 新增文章

```powershell
npx hexo new post "文章标题"
```

文章内的 `cover:` 可以单独指定封面；不写时从 `images.yml` 中随机取图。

## 部署到 GitHub Pages

仓库：<https://github.com/Clouds-remain/clouds-remain.github.io>

首次部署前，在仓库 **Settings → Pages → Build and deployment → Source** 中选择 **GitHub Actions**。免费账号的 Pages 仓库需要是 **public**。

之后每次推送到 `main` 分支，`.github/workflows/pages.yml` 会：

1. 用 Node.js 24 和 `npm ci` 安装依赖（npm 使用 npmmirror 镜像）
2. 执行 `npm run build`（Hexo + Pagefind）
3. 上传 `public/` 为 Pages artifact
4. 调用 GitHub Pages 官方部署 action 发布

也可以在 Actions 页面手动触发 `workflow_dispatch`。

### 为什么锁定 Hexo 7.3.0

ShokaX 0.5.4 的依赖声明是 `hexo ^7.3.0`，官方模板也锁在 7.3.0；`hexo init` 现在默认 Hexo 8，属于主题未声明兼容的组合。为稳定起见，本项目固定 `hexo@7.3.0`，并用锁文件保证 CI 与本地一致。

## 备注

- 仓库中不包含任何 token、密码或私钥。
- `node_modules/`、`public/`、`db.json`、`_setup/` 已被 `.gitignore` 忽略。
- 主题许可证为 AGPL-3.0-or-later；使用或修改前请阅读主题仓库的 `UsageRestrictions.md`。
