# Task31 My List And Watch Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用真实收藏、观看历史和播放进度替换 My List Mock 数据，并保证 For You、Series、My List 三处状态一致。

**Architecture:** 后端提供批量收藏状态和幂等播放会话进度合同；iOS 通过 `RealFavoritesRepository`、共享 `BookmarkStore` 和串行 `WatchProgressReporter` 隔离网络、状态与 UI。收藏以 bookmark 为唯一业务真相，My List 的 Following 只是显示文案，不使用第二套 follow 状态。

**Tech Stack:** SwiftUI, Swift Concurrency, AVFoundation, XCTest/Swift Testing, Spring Boot, MyBatis-Plus, MySQL 8, JUnit 5

---

## 执行边界

- iOS 仓库：`/Users/ethan/myspance/relaxshort/ios/v1.0.0`
- 后端仓库：`/Users/ethan/myspance/relaxshort/app-server/v2`
- 两个仓库分别提交，禁止跨仓库混合提交。
- 不新增长篇交付报告；本计划勾选状态和最终中文简报就是交付记录。
- 不删除后端旧 follow API/表，但 iOS 禁止调用它们。

### Task 1: 后端收藏状态与历史合同 RED 测试

**Files:**
- Create: `/Users/ethan/myspance/relaxshort/app-server/v2/src/test/java/com/relaxshort/v2/app/interaction/BookmarkStatusControllerTest.java`
- Modify: `/Users/ethan/myspance/relaxshort/app-server/v2/src/test/java/com/relaxshort/v2/app/user/UserControllerTest.java`
- Modify: `/Users/ethan/myspance/relaxshort/app-server/v2/src/test/java/com/relaxshort/v2/app/user/WatchProgressServiceTest.java`

- [ ] **Step 1: 编写批量收藏状态失败测试**

测试必须断言 `series_ids` 去重、最多 50 个、仅返回当前用户已收藏 ID：

```java
when(service.bookmarkedSeriesIds(1L, List.of(11L, 12L)))
        .thenReturn(Set.of(12L));

mvc.perform(get("/api/v2/users/me/bookmark-status")
        .header("X-User-Id", "1")
        .param("series_ids", "11,12"))
    .andExpect(status().isOk())
    .andExpect(jsonPath("$.data.bookmarked_series_ids[0]").value(12));
```

- [ ] **Step 2: 编写进度完整性与幂等失败测试**

覆盖以下精确行为：

```java
assertThrows(BizException.class, () -> service.report(1L, request(10L, 999L)));
verify(watchRecordMapper, never()).insert(any());

service.report(1L, heartbeat("session-a", false));
verify(watchHistoryMapper).insert(any());
verify(watchRecordMapper, never()).insert(any());

service.report(1L, heartbeat("session-a", true));
service.report(1L, heartbeat("session-a", true));
verify(watchRecordMapper, times(1)).insert(any());
```

- [ ] **Step 3: 编写历史 episode_number 失败测试**

```java
mvc.perform(get("/api/v2/watch-history")
        .header("X-User-Id", "1"))
    .andExpect(status().isOk())
    .andExpect(jsonPath("$.data.items[0].episode_number").value(3));
```

- [ ] **Step 4: 运行 RED 测试**

```bash
cd /Users/ethan/myspance/relaxshort/app-server/v2
mvn -Dtest='BookmarkStatusControllerTest,UserControllerTest,WatchProgressServiceTest' test
```

Expected: 新 endpoint、字段和会话幂等能力尚不存在，测试失败。

### Task 2: 实现后端生产合同

**Files:**
- Create: `/Users/ethan/myspance/relaxshort/app-server/v2/src/main/resources/db/migration/V15__watch_session_idempotency.sql`
- Create: `/Users/ethan/myspance/relaxshort/app-server/v2/src/main/java/com/relaxshort/v2/app/interaction/dto/BookmarkStatusResponse.java`
- Modify: `/Users/ethan/myspance/relaxshort/app-server/v2/src/main/java/com/relaxshort/v2/app/interaction/InteractionController.java`
- Modify: `/Users/ethan/myspance/relaxshort/app-server/v2/src/main/java/com/relaxshort/v2/app/interaction/InteractionService.java`
- Modify: `/Users/ethan/myspance/relaxshort/app-server/v2/src/main/java/com/relaxshort/v2/app/user/dto/WatchProgressRequest.java`
- Modify: `/Users/ethan/myspance/relaxshort/app-server/v2/src/main/java/com/relaxshort/v2/app/user/dto/WatchHistoryResponse.java`
- Modify: `/Users/ethan/myspance/relaxshort/app-server/v2/src/main/java/com/relaxshort/v2/app/user/WatchProgressService.java`
- Modify: `/Users/ethan/myspance/relaxshort/app-server/v2/src/main/java/com/relaxshort/v2/app/content/entity/EpisodeWatchRecord.java`
- Modify: `/Users/ethan/myspance/relaxshort/app-server/v2/src/main/java/com/relaxshort/v2/infrastructure/mapper/UserBookmarkMapper.java`

- [ ] **Step 1: 添加会话幂等迁移**

```sql
ALTER TABLE rs_episode_watch_records
    ADD COLUMN play_session_id VARCHAR(36) NULL COMMENT '客户端播放会话UUID' AFTER episode_id,
    ADD UNIQUE KEY uk_user_play_session (user_id, play_session_id);
```

- [ ] **Step 2: 实现批量收藏状态**

DTO：

```java
@Data
@Builder
public class BookmarkStatusResponse {
    private Set<Long> bookmarkedSeriesIds;
}
```

Controller：

```java
@GetMapping("/api/v2/users/me/bookmark-status")
public ApiResponse<BookmarkStatusResponse> bookmarkStatus(
        @RequestParam("series_ids") List<Long> seriesIds,
        HttpServletRequest request) {
    return ApiResponse.success(svc.bookmarkStatus(
            userCtx.requireUserId(request), seriesIds));
}
```

Service 必须先 `distinct()`，拒绝空列表和超过 50 个 ID，再用单条
`user_id + series_id IN (...)` 查询返回 Set。

- [ ] **Step 3: 扩展进度请求**

```java
private String playSessionId;
private Boolean finalReport;
```

校验 `playSessionId` 为 UUID；查询 episode 后断言 `episode.seriesId == request.seriesId`
且 episode status 为有效状态。

- [ ] **Step 4: 分离 heartbeat 与最终记录**

`rs_watch_histories` 每次都 upsert。只有以下条件成立才写
`rs_episode_watch_records`：

```java
boolean shouldFinalize = Boolean.TRUE.equals(req.getFinalReport()) || completed;
if (shouldFinalize && !watchRecordExists(userId, req.getPlaySessionId())) {
    insertFinalWatchRecord(...);
}
```

并发重复最终请求依赖唯一键兜底；捕获 `DuplicateKeyException` 后返回相同成功响应，
不得返回 500。

- [ ] **Step 5: 历史响应补 episode_number**

批量查询当前页 episode ID，建立 `episodeId -> episodeNumber` Map；禁止在循环里
逐条查询。`HistoryItem` 增加：

```java
private Integer episodeNumber;
```

- [ ] **Step 6: 运行后端测试与打包**

```bash
cd /Users/ethan/myspance/relaxshort/app-server/v2
mvn test
mvn package -DskipTests
git diff --check
```

Expected: 全部 exit 0，无失败、无 whitespace 错误。

- [ ] **Step 7: 提交后端**

```bash
git add src/main src/test
git commit -m "feat: add bookmark state and watch progress contracts"
```

### Task 3: iOS DTO、Endpoint 与 Repository RED 测试

**Files:**
- Create: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShortTests/FavoritesRepositoryContractTests.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShortTests/APIEndpointTests.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Core/Services/RepositoryProtocols.swift`

- [ ] **Step 1: 定义领域合同**

```swift
struct CursorPage<Item: Sendable>: Sendable {
    let items: [Item]
    let nextCursor: String?
    let hasMore: Bool
}

protocol FavoritesRepositoryProtocol: Sendable {
    func fetchWatchHistory(cursor: String?, limit: Int) async throws
        -> CursorPage<WatchHistoryItem>
    func fetchBookmarks(cursor: String?, limit: Int) async throws
        -> CursorPage<DramaItem>
    func fetchBookmarkedSeriesIDs(_ seriesIDs: [String]) async throws -> Set<String>
    func setBookmarked(_ bookmarked: Bool, seriesID: String) async throws -> Bool
    func reportProgress(_ report: WatchProgressReport) async throws
}
```

- [ ] **Step 2: 编写 endpoint 测试**

断言真实路径、HTTP 方法、query 参数、`X-User-Id`：

```swift
#expect(APIEndpoint.bookmarkStatus(seriesIDs: ["1", "2"]).path
        == "/api/v2/users/me/bookmark-status")
#expect(APIEndpoint.setBookmark(seriesID: "1", bookmarked: true).method == .post)
#expect(APIEndpoint.setBookmark(seriesID: "1", bookmarked: false).method == .delete)
#expect(APIEndpoint.watchProgress(report).headers["X-User-Id"] == "1")
```

- [ ] **Step 3: 编写 DTO 解码测试**

固定 JSON fixture 必须覆盖 `episode_number`、`next_cursor`、
`bookmarked_series_ids` 和 Int64 series ID，断言 `.convertFromSnakeCase`
只映射一次，不重复写错误 CodingKeys。

- [ ] **Step 4: 运行 RED 测试**

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: 新领域类型、endpoint 和 repository 尚不存在，测试失败。

### Task 4: 实现 iOS 真实数据层

**Files:**
- Create: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Models/API/FavoritesResponseDTO.swift`
- Create: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Models/WatchProgressReport.swift`
- Create: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Core/Services/RealFavoritesRepository.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Core/Services/APIEndpoint.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Core/Services/DependencyContainer.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Models/WatchHistory.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Core/Services/MockAPIRepository.swift`

- [ ] **Step 1: 新增真实 v2 endpoints**

```swift
case watchHistory(cursor: String?, limit: Int)
case watchProgress(WatchProgressReport)
case bookmarks(cursor: String?, limit: Int)
case bookmarkStatus(seriesIDs: [String])
case setBookmark(seriesID: String, bookmarked: Bool)
```

这些 endpoint 全部使用 `APIConfig.baseURL`、`X-Device-Id` 和用户身份头。DELETE
不得发送 `{}` body。

- [ ] **Step 2: 实现 DTO 到领域模型映射**

`HistoryItemDTO` 必须以 `card.toDramaItem()` 生成 `DramaItem`，并保留：

```swift
WatchHistoryItem(
    id: "\(seriesID)-\(episodeID)",
    drama: drama,
    episodeID: String(episodeID),
    currentEpisode: episodeNumber,
    resumeTime: TimeInterval(resumeTime),
    watchedAt: parseBackendDate(lastWatchedAt) ?? .distantPast,
    progress: min(max(progressPercent, 0), 1)
)
```

`FavoritesResponseDTO.swift` 内定义稳定解析器，兼容后端带/不带时区的 ISO 时间：

```swift
private func parseBackendDate(_ raw: String) -> Date? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: raw) { return date }

    let local = DateFormatter()
    local.locale = Locale(identifier: "en_US_POSIX")
    local.calendar = Calendar(identifier: .gregorian)
    local.timeZone = TimeZone(secondsFromGMT: 0)
    local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return local.date(from: raw)
}
```

- [ ] **Step 3: 实现 RealFavoritesRepository**

所有方法只调用真实 v2 endpoint。HTTP/解码失败原样抛出，不回退 Mock。

- [ ] **Step 4: 修正依赖注入**

```swift
self.favoritesRepository = favoritesRepository
    ?? (Self.useRealAPI ? RealFavoritesRepository() : MockFavoritesRepository())
```

把 initializer 参数改成 optional，避免默认参数提前固定 Mock。

- [ ] **Step 5: 运行合同测试转 GREEN**

重复 Task 3 Step 4 命令，Expected: tests passed。

### Task 5: 共享收藏状态

**Files:**
- Create: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Core/Stores/BookmarkStore.swift`
- Create: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShortTests/BookmarkStoreTests.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Core/Services/DependencyContainer.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Views/RecommendPage/RecommendView.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`

- [ ] **Step 1: 编写乐观更新与回滚测试**

```swift
@Test @MainActor
func failedBookmarkRestoresPreviousState() async {
    let repo = FavoritesRepositoryStub(setError: TestError.failed)
    let store = BookmarkStore(repository: repo)
    await store.toggle(seriesID: "10", sourceScene: "series")
    #expect(store.isBookmarked("10") == false)
    #expect(store.errorMessage != nil)
}
```

另测成功写入、批量状态只发一次请求、并发重复点击被同 series in-flight guard 拒绝。

- [ ] **Step 2: 实现 BookmarkStore**

```swift
@MainActor
final class BookmarkStore: ObservableObject {
    @Published private(set) var bookmarkedIDs: Set<String> = []
    @Published private(set) var pendingIDs: Set<String> = []
    @Published var errorMessage: String?
}
```

`toggle` 先更新 Set，服务端失败恢复 previous value。Analytics 在 repository 成功后
调用，取消收藏不得上报 bookmark-add 事件。

- [ ] **Step 3: For You 批量加载状态**

推荐页拿到当前 Feed page 后调用一次 `loadStatus(seriesIDs:)`。卡片切换只从 Store
读取，不为每张卡片请求网络。

- [ ] **Step 4: Series 加载与写入共享状态**

Series `.task(id: drama.id)` 查询当前 ID；右侧书签绑定 Store。页面退出不清空
Store，My List 可以立即看到更新。

- [ ] **Step 5: 运行 BookmarkStoreTests**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:RelaxShortTests/BookmarkStoreTests
```

Expected: passed。

### Task 6: 播放进度 Reporter 与生命周期

**Files:**
- Create: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Core/Playback/WatchProgressReporter.swift`
- Create: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShortTests/WatchProgressReporterTests.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/PlayerKit/PlayerCoordinator.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/RelaxShortApp.swift`

- [ ] **Step 1: 编写节流与最终补报测试**

使用注入的 `Clock`/sleep closure，不真实等待 15 秒。覆盖：

- 15 秒内多个 tick 只发送一次。
- 进度增长不足 3 秒不发送。
- pause/disappear/background 强制 `finalReport=true`。
- completion 强制 `completed=true`。
- 新 episode 创建新 UUID session。
- 老 session 的异步回调不能覆盖新 session。

- [ ] **Step 2: 实现 actor**

```swift
actor WatchProgressReporter {
    private var session: Session?
    private var lastSentSeconds = 0
    private var lastSentAt: ContinuousClock.Instant?

    func begin(seriesID: String, episodeID: String) async
    func observe(seconds: Int, duration: Int, metadata: PlaybackMetadata) async
    func finalize(completed: Bool) async
}
```

Reporter 内部 await repository，保证单会话串行；`finalize` 后清空 session。

- [ ] **Step 3: 接入 SeriesPlayerView**

在 episode 真正绑定 player 后 begin；`engine.$progress` 仅把快照传给 Reporter。
以下位置调用 finalize：

- 用户暂停。
- 切换 episode 前。
- `onDisappear` 在 Coordinator release 前。
- ScenePhase 进入 background。
- 当前 episode 播放完成。

- [ ] **Step 4: 使用后端 resume_time**

正式 play asset 返回后，若没有显式 handoff 且 `resumeTime > 0`，在自动播放前 seek；
接近结尾（`duration - resumeTime <= 3`）则从 0 开始，避免重进只看到尾帧。

- [ ] **Step 5: 运行进度与播放器回归测试**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:RelaxShortTests/WatchProgressReporterTests \
  -only-testing:RelaxShortTests/PlayerCoordinatorLifecycleTests
```

Expected: passed，退出后 engine owner 为 nil 且 `wantsPlayback=false`。

### Task 7: My List 真实 ViewModel

**Files:**
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/ViewModels/FavoritesViewModel.swift`
- Create: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShortTests/FavoritesViewModelTests.swift`

- [ ] **Step 1: 编写状态机测试**

覆盖 Following/History 首屏加载、分页去重、Retry、空态、切 tab 不重复清空、
批量删除部分失败、推荐榜单真实加载。

- [ ] **Step 2: 实现独立分页状态**

```swift
@Published private(set) var bookmarks: [DramaItem] = []
@Published private(set) var history: [WatchHistoryItem] = []
@Published private(set) var trending: [DramaItem] = []
@Published private(set) var selectedIDs: Set<String> = []
@Published private(set) var isEditing = false
```

Following 和 History 分别保存 `nextCursor/hasMore/isLoading/error`，禁止共用一个
`isLoading` 导致切页闪空。

- [ ] **Step 3: 实现批量删除结果**

对已选 ID 使用最多 3 个并发请求；成功项从 bookmarks 和 BookmarkStore 移除，
失败项保持选中。全部结束后只显示一条汇总错误。

- [ ] **Step 4: 运行 ViewModel 测试**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:RelaxShortTests/FavoritesViewModelTests
```

Expected: passed。

### Task 8: My List 响应式 UI

**Files:**
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Views/Favorites/FavoritesView.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Views/MainTabView.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Utils/LocalizationHelper.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Base.lproj/Localizable.strings`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/en.lproj/Localizable.strings`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/zh-Hans.lproj/Localizable.strings`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/zh-Hant.lproj/Localizable.strings`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/es.lproj/Localizable.strings`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/pt.lproj/Localizable.strings`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/ja.lproj/Localizable.strings`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/ko.lproj/Localizable.strings`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/ar.lproj/Localizable.strings`

- [ ] **Step 1: 注入真实 ViewModel**

`MainTabView` 用 `dependencies.favoritesRepository`、`dependencies.homeRepository`
和共享 `bookmarkStore` 创建 FavoritesViewModel。删除 FavoritesView initializer
内硬编码的 `MockFavoritesRepository()`。

- [ ] **Step 2: 实现顶部和编辑态**

普通态显示 Following / History 和右侧 `slider.horizontal.3` 编辑图标；编辑态显示
Choose / Cancel。只有 Following 非空时可进入编辑。选中颜色统一 `DB.logoRed`，
不使用 `DB.pink`。

- [ ] **Step 3: 实现统一列表行**

使用一个 `MyListRow` 组件承载普通/编辑态。封面宽度按可用宽度约束：

```swift
let coverWidth = min(max(containerWidth * 0.22, 72), 96)
let coverHeight = coverWidth * 1.5
```

标题单行、标签单行截断、EP 行固定，进度线贴封面底部。不得写设备型号判断。

- [ ] **Step 4: 实现真实导航**

Following 点击从第 1 集或服务端可用入口播放；History 点击传
`episodeID/currentEpisode/resumeTime`，确保播放所选历史而不是第 1 集。

- [ ] **Step 5: 实现 Most Trending**

三列网格使用真实 trending 数据、统一 `DB.posterRadius`，不读取
`MockData.homePopular`。

- [ ] **Step 6: 补齐 9 套本地化**

新增并完整翻译：

`my_list.following`、`my_list.history`、`my_list.choose`、`common.cancel`、
`common.remove`、`my_list.most_trending`、`my_list.empty_following`、
`my_list.empty_history`、`common.retry`。

- [ ] **Step 7: 删除 Real 路径 Mock**

```bash
rg -n "MockData|MockFavoritesRepository" \
  RelaxShort/Views/Favorites \
  RelaxShort/ViewModels/FavoritesViewModel.swift
```

Expected: 0 matches。

### Task 9: 端到端联调与质量门禁

**Files:**
- Modify only when a verified defect is found.

- [ ] **Step 1: 后端空库迁移**

用 `docker-compose.mysql.yml` 的 MySQL 8.4 新建临时空库，执行 Flyway V1-V15，
确认 schema history 全部 success。

- [ ] **Step 2: API smoke**

按顺序验证：

1. POST bookmark。
2. GET bookmark-status 命中。
3. GET bookmarks 列表出现。
4. POST heartbeat 后 GET watch-history 出现进度和 episode_number。
5. 重复 POST 相同 final session，`rs_episode_watch_records` 仅一条。
6. DELETE bookmark 后列表和 status 同时消失。

- [ ] **Step 3: iOS 真实模拟器验收**

在 iPhone 17 上完成：

1. For You 收藏，My List Following 立即出现。
2. Series 取消收藏，Following 立即移除。
3. 播放 20 秒退出，无漏音。
4. History 显示正确集数和进度。
5. 从 History 进入所选 episode，从后端 resume_time 自动续播。
6. 编辑多选移除，成功项消失，失败项可 Retry。

- [ ] **Step 4: 三尺寸验证**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation),OS=17.0'
xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

Expected: 全部 exit 0；列表文字不重叠，编辑底栏不压 safe area。

- [ ] **Step 5: 性能 smoke**

对 bookmarks、watch-history、bookmark-status 各执行 100 请求、并发 10；
本地错误率 0%，p95 小于 300ms。检查 SQL 日志无 N+1。

- [ ] **Step 6: 最终测试与 diff**

```bash
cd /Users/ethan/myspance/relaxshort/app-server/v2
mvn test
mvn package -DskipTests
git diff --check

cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17'
git diff --check
```

- [ ] **Step 7: 分仓提交**

```bash
cd /Users/ethan/myspance/relaxshort/app-server/v2
git add src
git commit -m "feat: complete My List backend contracts"

cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
git add RelaxShort RelaxShortTests
git commit -m "feat: connect My List and watch progress"
```

最终只输出：修改文件摘要、测试结果、真实 API smoke 结果、仍存在的风险。不要另写
重复的长篇交付报告。
