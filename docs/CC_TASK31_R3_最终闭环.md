# Task31 R3 最终闭环实施计划

**目标：** 在 `a37cda2` 基础上修复真实收藏/历史不刷新、真实续播、进度上报并发、分页/删除错误状态，并按 DramaBox 参考图完成 My List UI。

**边界：** 只修改下列明确文件，不重做现有 My List 视觉结构，不修改后端，不新增交付报告。

---

## Task 1：打通真实 Following 和 History 数据闭环

**文件：**

- `RelaxShort/Views/Favorites/FavoritesView.swift`
- `RelaxShort/ViewModels/FavoritesViewModel.swift`
- `RelaxShort/Views/MainTabView.swift`
- 必要时更新对应 ViewModel/Repository 测试

### 根因

`TabContentHost` 中所有 Tab 常驻，只通过 `opacity/zIndex` 切换。`FavoritesView.onAppear` 通常只在应用创建时执行一次：

1. My List 首次加载为空。
2. 用户去 Home/播放器点击收藏或产生观看历史。
3. 返回 My List 时没有再次请求 bookmark/history。
4. 页面继续显示旧的空数组。

另外，`DependencyContainer.useRealAPI == false` 时使用无状态 `MockFavoritesRepository`；`setBookmarked` 不会改变下一次 `fetchBookmarks` 的结果。真实验收必须明确运行真实 API，不得用 Mock 结果声称功能完成。

### 修复

增加明确的用户数据刷新入口：

```swift
func refreshUserData() async {
    async let bookmarks: () = loadBookmarks()
    async let history: () = loadHistory()
    _ = await (bookmarks, history)
}
```

`FavoritesView` 必须响应 My List Tab 从非激活变为激活：

```swift
.onChange(of: appStore.selectedTab) { _, tab in
    guard tab == .myList, authStore.isLoggedIn else { return }
    Task { await viewModel.refreshUserData() }
}
```

同时：

- 登录成功后立即刷新 bookmark/history。
- App 从后台回到 active 且当前是 My List 时刷新。
- Trending 只在未加载或用户主动 Retry 时加载，不因每次切 Tab 重复请求。
- 刷新失败保留已有数据，显示错误，不回退 Mock。
- 刷新后的 bookmark 列表必须和 `BookmarkStore` 同步；服务端取消的项目不得残留。

### 真实 API smoke

CC 必须使用：

```text
use_real_api=true
api_base_url=当前本地后端地址
X-User-Id=1（当前 local/dev 桥）
```

完成以下真实 UI 流程并在聊天中报告结果：

1. 从 Home 进入一部剧。
2. 点击收藏，确认按钮变为已收藏。
3. 切到 My List，Following 必须出现同一部剧。
4. 返回播放器播放至少 5 秒后退出。
5. 再进入 My List → History，必须出现真实 episode、进度和 resume time。
6. 取消收藏后重新进入 My List，该剧必须从 Following 消失，但 History 仍保留。

同时用后端请求日志或 curl 证明同一用户写入和读取：

```text
POST   /api/v2/series/{seriesId}/bookmark
GET    /api/v2/users/me/bookmarks
POST   /api/v2/watch-progress
GET    /api/v2/watch-history
```

新增测试：

- `refreshUserData()` 同时刷新 bookmarks/history。
- 新收藏后再次刷新能更新空列表。
- History 刷新后使用最新 episode/progress。
- 一个请求失败不清空另一个成功列表。

## Task 2：修复 My List resume 计算后未传入播放器

**文件：**

- `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`
- `RelaxShortTests/PlayerCoordinatorTests.swift` 或新增聚焦的续播测试文件

当前错误：

```swift
let effectiveResume = handoff?.resumeTime ?? myListResume ?? backendResume
```

计算后调用仍是：

```swift
backendResumeTime: backendResume
```

必须改为把实际选中的 resume 传入：

```swift
playerCoordinator.claimSeries(
    drama: drama,
    items: playerItems,
    startIndex: startIndex,
    handoff: handoff,
    backendResumeTime: handoff == nil ? (myListResume ?? backendResume) : backendResume
)
```

同时修复初始 episode 流程：

- `loadEpisodes()` 后先根据 `initialEpisodeID` 确定 `currentEpisode`。
- 再为最终确定的 episode 调用 `ensurePlayAsset` 和 `initializeEpisodePlayer`。
- 不允许先初始化旧 episode，再依赖 `onChange` 二次切换。
- `initialResumeTime` 只消费一次；切换下一集后只使用该集 play asset resume。

新增失败优先测试：

- My List resume 为 42 秒、play asset resume 为 10 秒时选择 42。
- handoff 为 25 秒时选择 25。
- 切换下一集后不再选择 42。
- `initialEpisodeID` 匹配的 episode number 优先于路由中的错误 startEpisode。

## Task 3：实现 WatchProgressReporter 真正串行发送

**文件：**

- `RelaxShort/Core/Playback/WatchProgressReporter.swift`
- `RelaxShortTests/WatchProgressReporterTests.swift`

建立同一 reporter 内唯一发送链。后一请求必须等待前一请求完成后才调用 repository：

```swift
private var sendTail: Task<Void, Never>?

private func enqueue(_ operation: @escaping @Sendable () async -> Void) async {
    let previous = sendTail
    let current = Task {
        await previous?.value
        await operation()
    }
    sendTail = current
    await current.value
}
```

可以采用等价实现，但必须满足：

- heartbeat 和 final 共用同一队列。
- 多个并发 `observe` 只能预约一个合格 heartbeat；需要 `heartbeatPending` 或 session generation/token 防重。
- heartbeat 成功后才更新节流状态。
- final 排在已预约 heartbeat 后。
- 新 session 不等待旧 session 状态清理，但网络写入顺序不能反转。
- 删除当前未实际使用的 `generation` 参数，或让它参与 token 判断。

使用可控 gate/continuation 新增测试，禁止用长 sleep 猜时序：

1. 同时调用三个 `observe`，repository 只收到一个 heartbeat。
2. heartbeat 被 gate 阻塞时调用 final，释放 gate 后顺序严格为 heartbeat、final。
3. 旧 final 等待期间创建新 session，旧请求完成后新 session 仍 active。
4. final 使用最新 progress 和真实 duration。

## Task 4：完善 Remove 部分失败和编辑生命周期

**文件：**

- `RelaxShort/ViewModels/FavoritesViewModel.swift`
- `RelaxShort/Views/Favorites/FavoritesView.swift`
- `RelaxShortTests/FavoritesViewModelTests.swift`

ViewModel 增加：

```swift
@Published var removalError: String?
```

行为：

- 开始删除时清空 `removalError`。
- 部分失败时成功项移除，失败项保留选择，并设置 `L10n.myListPartialRemoveFailed`。
- 全部成功才退出编辑。
- `cancelEditing()` 同时清空错误。

View：

- 在 Remove 栏上方显示一条汇总错误，不弹多条 alert。
- `handleDisappear()` 必须调用 `viewModel.cancelEditing()`，并无条件恢复 `isBottomTabBarHidden = false`。
- 登录态变为 false 时同样退出编辑并恢复 Tab Bar。
- 返回 My List 时不能出现“仍在编辑但主 Tab Bar 已显示”的矛盾状态。

新增测试：

- 全部删除成功。
- 部分失败时成功项消失、失败项保留选择、错误存在。
- 重复点击 Remove 只执行一轮请求。
- cancel 清空选择和错误。

## Task 5：修复分页 Retry 语义

**文件：**

- `RelaxShort/ViewModels/FavoritesViewModel.swift`
- `RelaxShort/Views/Favorites/FavoritesView.swift`
- `RelaxShortTests/FavoritesViewModelTests.swift`

当前分页错误 footer 调用 `loadBookmarks()` / `loadHistory()`，会重新请求第一页。

分别保存首页错误和分页错误，或者增加明确的分页 Retry：

```swift
func retryBookmarks() async {
    if bookmarks.isEmpty {
        await loadBookmarks()
    } else {
        await loadMoreBookmarks()
    }
}
```

History 使用同样规则。

要求：

- 下一页失败保留已有列表和 cursor。
- Retry 使用原 cursor。
- sentinel 只在 `hasMore == true` 时存在。
- `isLoading` 防止 sentinel 重建产生重复并发请求。

新增测试：

- 下一页追加并按 ID 去重。
- 下一页失败不清空首页。
- Retry 参数仍是失败页 cursor。
- `hasMore == false` 不请求。

## Task 6：按 DramaBox 截图完成 My List UI

**文件：**

- `RelaxShort/Views/Favorites/FavoritesView.swift`
- `RelaxShort/ViewModels/FavoritesViewModel.swift`
- `RelaxShort/Utils/LocalizationHelper.swift`
- 所有现有 `Localizable.strings`

CC 不需要识图。以下文字是截图的强制视觉合同。

### 顶部栏

- 页面纯黑，不显示 `My List` 导航标题。
- 只保留 Following、History，不显示 Reminder Set。
- Following/History 位于左侧，字号约 20pt。
- 选中项白色 semibold，未选中项约 55% 白色。
- 选中项下方必须有宽约 28pt、高 3pt 的短横线。
- Following 状态下右侧始终显示 `slider.horizontal.3` 编辑按钮；无收藏时禁用并降低透明度，不能直接消失导致顶部布局跳动。
- 点击编辑必须进入完整 Choose/Cancel/选择圆/Remove 流程。

### Following 和 History 行

- 黑色平面列表，无卡片背景、描边、阴影、chevron。
- 页面水平边距 16pt，相邻行间距约 18pt。
- 海报宽度：

```swift
min(max(containerWidth * 0.22, 72), 92)
```

- 海报固定 2:3、使用 `DB.posterRadius`。
- 标题 17pt semibold；题材标签 15pt 灰色；集数 16pt 灰色。
- 标签组合 category、regionTag、languageTag、tags 中真实非空字段，不显示空分隔符。
- 海报底部 3pt 进度线，红色进度限制在 `0...1`。
- 已选择的 45% 黑色遮罩必须位于海报图和进度线之间，不能遮住红色进度线。

### Most Trending

只显示热门排行前 6 个：

```swift
let topSix = trendingEntries
    .sorted { $0.rankPosition < $1.rankPosition }
    .prefix(6)
```

- 固定三列两行，不加载第 7 项，不做该区域分页。
- 标题为 `Most Trending`，左对齐，无彩色竖线。
- 封面保持 2:3，列间距约 10pt，行间距约 18pt。
- 每张封面左上角必须显示排名角标：
  - 1：橙/金色。
  - 2：绿色。
  - 3：蓝色。
  - 4–6：深灰色。
- 角标约 26×26pt，数字白色 semibold，与封面左上角贴合。
- 热度值可使用 flame + metric 叠在封面右下角。
- 封面下方显示标题，最多两行；再显示 category/首个 tag，灰色单行。
- 第六项后显示本地化 `No more content`。
- 点击任意榜单卡进入对应剧集。

### 编辑态

- 顶部显示居中 Choose，右侧 Cancel。
- 每行左侧选择圆与海报垂直居中。
- 已选中圆为红色实心加白色 checkmark。
- 已选海报变暗，但文字和底部红色进度线不变暗。
- 编辑时隐藏主 Tab Bar，只显示固定 Remove 栏。
- Remove 成功必须真实取消服务端 bookmark；取消编辑恢复正常 Tab Bar。

### 可测试数据

ViewModel 暴露纯派生结果，便于测试：

```swift
var topTrendingEntries: [RankingEntry] {
    Array(trendingEntries.sorted {
        $0.rankPosition < $1.rankPosition
    }.prefix(6))
}
```

新增测试：

- 输入乱序 8 项时输出严格为排名 1...6。
- 不包含第 7、8 项。
- 编辑按钮在 Following 保持占位；无数据时禁用，有数据时可进入编辑。

## Task 7：补齐本地化与无障碍

**文件：**

- 所有现有 `Localizable.strings`
- `RelaxShort/Utils/LocalizationHelper.swift`
- `RelaxShort/Views/Favorites/FavoritesView.swift`

当前还缺少：

```text
my_list.selection_selected
my_list.selection_unselected
my_list.remove_selected_count
my_list.no_more_content
```

所有 Base/en/zh-Hans/zh-Hant/es/pt/ja/ko/ar 都必须存在。

UI 必须使用：

```swift
.accessibilityValue(
    isSelected ? L10n.myListSelectionSelected : L10n.myListSelectionUnselected
)
```

Remove 使用本地化选择数量：

```swift
.accessibilityLabel(
    L10n.myListRemoveSelectedCount(viewModel.selectedBookmarkIDs.count)
)
```

标签行不能只显示 category；按可用值组合 category、regionTag、languageTag、tags，过滤空字符串后再连接。

## Task 8：验证与提交

先运行定向测试：

```bash
xcodebuild test -quiet \
  -project RelaxShort.xcodeproj \
  -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:RelaxShortTests/BookmarkStoreTests \
  -only-testing:RelaxShortTests/WatchProgressReporterTests \
  -only-testing:RelaxShortTests/PlayerCoordinatorTests \
  -only-testing:RelaxShortTests/FavoritesViewModelTests
```

再运行一次全量测试和三种尺寸构建：

```bash
xcodebuild test -quiet -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17'

xcodebuild build -quiet -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation),OS=17.0'

xcodebuild build -quiet -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'

git diff --check
```

创建新 commit：

```bash
git commit -m "fix: close Task31 My List remaining gaps"
```

返回 commit hash、测试 exit code、三种构建结果和仍未完成项。不要 push，不要声称视觉已经通过；视觉截图由 Codex 验收。
