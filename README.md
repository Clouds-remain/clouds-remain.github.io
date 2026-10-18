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
- **评论：已写好 Twikoo / Waline 配置模板，但保持关闭**
- **音乐播放器：保持关闭**
- **鼠标烟花：保持关闭**

## 后续修改

### 换头像或封面

- 头像：替换 `source/_data/assets/avatar.jpg` 后重新构建
- 封面：替换 `source/images/covers/cover-1.jpg` 到 `cover-6.jpg`，并在 `source/_data/images.yml`、`images_index.yml` 中保持 6 条路径
- 首页固定封面：修改 `_config.shokax.yml` 的 `homeConfig.fixedCover`

### 开启评论

在 `_config.shokax.yml` 中选择一种：

```yaml
# Waline
waline:
  enable: true
  serverURL: "https://your-waline.example.com"
```

```yaml
# Twikoo
twikoo:
  enable: true
  mode: vercel
  envId: "https://your-twikoo.example.com"
```

两套服务都需要单独部署，主题不会替你创建后端。

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
