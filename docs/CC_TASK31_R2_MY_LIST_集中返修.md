# Task31 R2：My List 集中返修

## 目标

在 commit `56502cd` 基础上，只修复 Codex 验收发现的缺口，使 My List 的编辑删除、分页、多语言、真实历史续播和观看进度并发安全达到 Task31 验收标准。

不要重写已经通过测试的 API、DTO、Repository 和现有平面列表基础布局。

最终创建一个新的独立 commit，不要 amend `56502cd`，不要 push。

## 开始前

1. 阅读根目录和 iOS 仓库的 `AGENTS.md`、`CLAUDE.md`。
2. 阅读 `docs/CC_TASK31_MY_LIST_VISUAL_CONTRACT.md`。
3. 查看 `git show --stat 56502cd`，然后只查看本任务涉及文件。
4. 确认工作区干净；不得混入其他任务。

## 一、P0：打通真实 History 续播导航

当前问题：

- `SeriesPlayerNav` 已保存 `episodeID` 和 `resumeTime`。
- `FavoritesView` 创建路由时也传入了真实值。
- 但 `MainTabView` 创建 `SeriesPlayerView` 时完全丢弃这两个字段。
- `SeriesPlayerView` 初始化器也没有对应参数，因此当前 History 点击并没有真实续播。

修复要求：

1. `SeriesPlayerView` 增加：

```swift
let initialEpisodeID: String?
let initialResumeTime: TimeInterval?
```

2. `MainTabView` 的两个 `SeriesPlayerView` 导航入口都必须传递：

```swift
initialEpisodeID: nav.episodeID
initialResumeTime: nav.resumeTime
```

3. 剧集列表加载完成后：

- 如果 `initialEpisodeID` 能匹配后端剧集，使用该剧集的真实 `episodeNumber`。
- 匹配失败才回退 `startEpisode`。
- My List 的显式续播时间只允许用于初始剧集一次。
- 用户切换到其他剧集后，不得继续携带初始剧集的 resume time。

4. 播放优先级：

```text
For You handoff > My List initial resume > play asset resume > 0
```

5. 新增测试：

- 路由保留 `episodeID`、`episodeNumber`、`resumeTime`。
- `MainTabView`/播放器初始化使用 My List resume。
- 初始 resume 不泄漏到下一集。
- For You handoff 仍然最高优先。

## 二、P0：WatchProgressReporter 必须真正串行发送

当前问题：

- 代码注释声称 heartbeat/final 串行，但没有发送队列。
- `send(...generation:)` 的 generation 参数没有参与任何判断。
- actor 在 repository `await` 时会重入；多个并发 tick 可能同时看到旧的 `lastSentInstant`，形成重复 heartbeat。
- 较旧 heartbeat 可能晚于 final 到达后端并覆盖最终进度。

修复要求：

- 在 reporter 内建立单一发送链/队列，后一请求必须等待前一请求完成后再调用 repository。
- heartbeat 和 final 都进入同一队列。
- 只有 heartbeat 成功后才更新 `lastSentSeconds/lastSentInstant`。
- final 使用最新快照，并排在此前 heartbeat 之后。
- 旧 session 响应不能清除或更新新 session。
- 删除无实际作用的 generation 参数，或者让它真正参与 session token 校验；不能只保留注释。

新增并发测试：

1. 同时发起多个 `observe`，15 秒窗口内 repository 只收到一个 heartbeat。
2. heartbeat 被延迟时调用 final，repository 接收顺序必须是 heartbeat → final。
3. final 后创建新 session，旧请求完成不能清除新 session。
4. final 的 progress/duration 使用最新真实值。

测试必须使用可控 continuation/gate，不要依赖长时间 sleep。

## 三、P1：修复 BookmarkStore 查询与 toggle 竞态

当前问题：

- `seriesVersions` 只在 toggle 网络请求成功后递增。
- 在乐观更新已经发生、网络尚未返回期间，迟到的 `loadStatus` 仍可能用旧响应覆盖乐观状态。
- 现有测试通过 `applyServerState` 模拟版本变化，没有真正测试并发 `toggle`。

修复要求：

- toggle 开始、执行乐观更新前立即递增该 series 的版本。
- 成功响应只应用于当前 mutation token。
- 失败回滚也必须保持版本前进，旧 loadStatus 不能重新覆盖回滚结果。
- `loadStatus` 只更新请求开始后版本未变化的 ID。

替换现有伪并发测试：

- 真实并发启动延迟 `loadStatus`。
- 等待其进入 repository 后调用 `toggle`。
- 分别验证 add 和 remove 两个方向。
- 释放迟到查询后，最终状态必须保持 toggle 的服务端结果。

## 四、P1：完成编辑态和 Remove 底栏

当前问题：

- `removeSelectedBookmarks()` 有基础实现，但 UI 没有 Remove 栏。
- 进入编辑态时没有任何代码设置 `appStore.isBottomTabBarHidden = true`。
- 页面底部 padding 当前是无效的 `0 : 0`。
- 没有部分删除失败汇总错误展示。

使用以下结构：

```swift
.onChange(of: viewModel.isEditing) { _, editing in
    appStore.isBottomTabBarHidden = editing
}
.safeAreaInset(edge: .bottom, spacing: 0) {
    if viewModel.isEditing {
        removeBar
    }
}
```

要求：

- Remove 栏纯黑、顶部 0.5pt 分隔线、内容高度 56pt。
- 右侧显示 trash 图标和本地化 Remove。
- 无选择时禁用并降低透明度。
- 删除中显示进度或禁用，禁止重复提交。
- 有失败项时成功项消失，失败项保留选择，并显示一条本地化汇总错误。
- Cancel、删除全部成功、退出页面、切换登录态时必须恢复主 Tab Bar。
- 编辑态不能显示主 Tab Bar 和 Remove 栏重叠。
- 最后一行必须能滚动到 Remove 栏上方。

## 五、P1：接入分页触发

在 Following 和 History 的最后一行使用稳定触发方式：

- 最后一项出现时分别调用 `loadMoreBookmarks()` / `loadMoreHistory()`。
- ViewModel 的 `isLoading + hasMore` 继续作为重复请求保护。
- 加载下一页时只显示底部小型 ProgressView，不遮挡已有内容。
- 分页结果按 ID 去重。
- 分页失败保留已有数据，Retry 继续请求当前 cursor，不得错误地重新加载第一页。

为此将“首页 Retry”和“下一页 Retry”分开处理，或者在 ViewModel 保存对应失败阶段。

新增测试：

- 最后一项只触发一次下一页。
- 下一页追加且去重。
- 下一页失败不清空首页。
- 下一页 Retry 使用原 cursor。

## 六、P1：补齐所有本地化和无障碍

当前 `my_list.*` 只存在于 `LocalizationHelper` fallback，没有写入任何 `.strings`。

必须在所有现有本地化文件中增加：

```text
my_list.login_guide
my_list.sign_in
my_list.following
my_list.history
my_list.choose
my_list.remove
my_list.most_trending
my_list.empty_following
my_list.empty_history
my_list.load_failed
my_list.partial_remove_failed
my_list.episode_progress
my_list.selection_selected
my_list.selection_unselected
my_list.remove_selected_count
```

覆盖：

- Base
- en
- zh-Hans
- zh-Hant
- es
- pt
- ja
- ko
- ar

同时：

- 删除 `FavoritesView` 中硬编码的 `Sign In`。
- 删除硬编码 `EP.x / EP.y`，改用本地化格式。
- 选择圆提供 selected/unselected accessibility value。
- Remove 提供当前选择数量的 accessibility label。
- 阿拉伯语使用系统 RTL，不手工翻转数组。

## 七、P1：补齐 UI 状态与测试

修复以下遗漏：

- Trending 首次加载时显示独立 ProgressView。
- Trending 空数据明确显示结束/空态，不留无反馈空白。
- 标签行组合 category、region、language 或 tags 中真实可用字段，不显示空分隔符。
- 页面退出时无条件清理编辑态和主 Tab Bar 隐藏状态。

扩展 `FavoritesViewModelTests`，至少覆盖：

- bookmarks/history/trending 独立成功与独立失败。
- 编辑进入、选择、取消。
- 删除全部成功。
- 部分删除失败。
- 重复 Remove 不重复请求。
- history lookup 与无历史 fallback。
- bookmark/history 分页和 Retry。

不得继续用“只有加载首页的 7 个旧测试”作为 Task31 UI 验收。

## 八、验证

先运行定向测试：

```bash
xcodebuild test -quiet \
  -project RelaxShort.xcodeproj \
  -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:RelaxShortTests/APIEndpointTests \
  -only-testing:RelaxShortTests/FavoritesRepositoryContractTests \
  -only-testing:RelaxShortTests/BookmarkStoreTests \
  -only-testing:RelaxShortTests/WatchProgressReporterTests \
  -only-testing:RelaxShortTests/PlayerCoordinatorTests \
  -only-testing:RelaxShortTests/FavoritesViewModelTests
```

再运行一次全量测试：

```bash
xcodebuild test -quiet \
  -project RelaxShort.xcodeproj \
  -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

完成三种尺寸构建：

```bash
xcodebuild build -quiet -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation),OS=17.0'

xcodebuild build -quiet -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17'

xcodebuild build -quiet -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

最后运行：

```bash
git diff --check
```

CC 不得自行声称视觉完全一致。Codex 会在 R2 提交后运行 App，分别截取普通态和编辑态，与 DramaBox 参考图进行视觉验收。

## 九、提交

只提交本次 R2 相关文件：

```bash
git commit -m "fix: complete Task31 My List acceptance gaps"
```

聊天中返回：

- 新 commit hash
- 修改区域
- 定向测试、全量测试、三种尺寸构建的真实 exit code
- 仍未完成的内容

不要新增交付报告，不要 push。
