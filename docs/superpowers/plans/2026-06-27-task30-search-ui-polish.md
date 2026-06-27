# Task30 Search UI Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按已确认设计修正 Search 搜索词来源、搜索框高度、响应式榜单分页、热度样式、前三名背景和排名角标。

**Architecture:** 扩展 `SearchRepositoryProtocol` 读取真实 suggestions，由 `SearchDefaultViewModel` 独立加载热门词；分页尺寸全部由容器比例计算；榜单卡片继续由统一组件维护。

**Tech Stack:** SwiftUI、Combine、现有 Repository/ViewModel 架构、`/api/v2/search/default`

---

### Task 1：真实 Trending Searches

**Files:**

- Modify: `RelaxShort/Core/Services/RepositoryProtocols.swift`
- Modify: `RelaxShort/Core/Services/RealSearchRepository.swift`
- Modify: `RelaxShort/Core/Services/MockAPIRepository.swift`
- Modify: `RelaxShort/ViewModels/SearchDefaultViewModel.swift`
- Modify: `RelaxShort/Views/Search/SearchView.swift`
- Modify: `RelaxShort/Views/Search/SearchDefaultView.swift`

- [ ] 在 `SearchRepositoryProtocol` 新增 `fetchSuggestions() async throws -> [String]`。
- [ ] Real Repository 从 `/api/v2/search/default` 返回 `suggestions`。
- [ ] Mock Repository 返回最多六个真实 Mock 剧名。
- [ ] Default ViewModel 注入 Search Repository，加载 suggestions 失败只记录日志，不阻断榜单。
- [ ] 有历史时显示 Recent Searches；无历史时显示 Trending Searches 和 suggestions。
- [ ] 热门词点击后执行真实搜索并写入历史。

### Task 2：响应式分页和标题

**Files:**

- Modify: `RelaxShort/Views/Search/SearchRankingPager.swift`
- Modify: `RelaxShort/Views/Search/SearchDefaultView.swift`
- Modify: `RelaxShort/Views/Search/SearchView.swift`

- [ ] 搜索框高度由 44 改为与 Home 相同的 36。
- [ ] 榜单页宽改为容器宽度 `0.84`，左边距 `0.04`，间距 `0.025`。
- [ ] 尾部 margin 按容器比例计算，保证第三页完整吸附。
- [ ] Tab 标题改为 16pt，选中 semibold，保持单行。

### Task 3：榜单卡片视觉

**Files:**

- Modify: `RelaxShort/Views/Search/SearchRankTheme.swift`
- Modify: `RelaxShort/Views/Search/SearchRankCardView.swift`

- [ ] 前三名卡片由低饱和主题色渐变到纯黑。
- [ ] 热度图标 14pt、数值 14pt bold，均为白色。
- [ ] 排名角标与封面左上边缘贴齐，不保留 padding。
- [ ] 角标背景从实色渐变到浅色，仅左上角使用 `DB.posterRadius`。

### Task 4：多语言与验证

**Files:**

- Modify: `RelaxShort/Utils/LocalizationHelper.swift`
- Modify: `RelaxShort/*/Localizable.strings`

- [ ] 九语言补齐 `search.trending_searches`。
- [ ] 执行九语言 key/value 检查和 `plutil -lint`。
- [ ] smoke `/api/v2/search/default` suggestions 非空。
- [ ] 执行 `git diff --check`。
- [ ] 执行 iPhone 17 Pro Max clean build，预期 `BUILD SUCCEEDED`。
- [ ] 等待用户进行小屏、标准屏、大屏模拟器视觉验收。
