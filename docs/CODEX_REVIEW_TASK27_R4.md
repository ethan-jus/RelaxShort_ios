# Task27 R4 Codex 复审结论

日期：2026-06-24
结论：不通过，必须返工。

## 总结

R4 没有达到任务书验收标准。主要问题不是“还差一点美化”，而是几个核心阻塞仍然存在：

- Home 搜索栏位置修反了，变得更低。
- Rankings 接口仍然 500，所以 App 没数据是后端真实问题。
- V7 排行数据没有通过 Flyway 正常记录，仍是手动导入状态。
- Home 接口虽然 200，但 sections 仍然全空。
- Categories UI 仍然是本地硬编码筛选矩阵，没有按参考图做出 DramaBox 风格，也没有后端字典联动。
- Task27 真实联调路径仍存在 MockData 兜底，不符合“真实接口数据测试”的要求。

## P0/P1 问题

### P0：Rankings 接口仍然 500

证据：

```bash
curl 'http://127.0.0.1:8080/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL'
```

实际返回：

```json
{"error":{"code":"INTERNAL_ERROR","message":"Internal server error"}}
```

R4 交付报告自己也写了 `curl /api/v2/rankings?... ❌ 500`。这与 R4 任务书“Rankings API returns 200 with multiple items”直接冲突。只写“数据正确在 MySQL”没有意义，App 调的是 API，不是直接读 MySQL。

### P0：V7 没有进入 Flyway 历史

本地数据库验证：

```sql
SELECT version, success FROM flyway_schema_history ORDER BY installed_rank;
```

实际只有 V1-V6，没有 V7。R4 报告写“V7 applied manually”，这不是可交付状态。迁移文件存在但未被 Flyway 管理，下一次重建库或其他机器联调都会不一致。

### P1：Home 搜索栏位置修反了

当前代码：

```swift
.padding(.top, geo.safeAreaInsets.top + HomeMetrics.searchTopGap)
```

这会在 VStack 内额外增加 safe area 顶部高度，把搜索栏往下推。用户反馈“搜索栏位置更低了”符合代码行为。

这里应该建立清晰的顶部布局契约：整个 Home 内容默认在安全区内布局时，不要再给搜索栏重复叠加 `safeAreaInsets.top`。如果确实使用全屏背景，只应该给一个很小的 `topGap`，或者把顶部 chrome 放进 `.safeAreaInset(edge: .top)` 统一管理。

### P1：Categories 仍然是硬编码 UI，不是后端字典联动

当前代码仍然在 `HomeView.swift` 里写死：

```swift
catsFilterRow(label: "Region", opts: ["All","US","Korea","China"], sel: $catRegion)
catsFilterRow(label: "Access", opts: ["All","Free","Member"], sel: $catAccess)
catsFilterRow(label: "Theme", opts: ["All","Boss","Revenge","Mafia","Werewolf"], sel: $catTheme)
catsFilterRow(label: "Sort", opts: ["Trending","Newest"], sel: $catSort)
```

这不满足用户要求：

- 语言、地区应该来自后端数据库或配置。
- UI 要参考 DramaBox：文字筛选行、选中粉色 pill、未选中灰色文字、大间距、内容网格自然接在筛选区下面。
- 不应该继续把筛选项埋在 HomeView 里。

### P1：真实联调路径仍然有 MockData 兜底

当前代码：

```swift
private var featuredOrEmpty: [DramaItem] {
    viewModel.featuredDramas.isEmpty ? MockData.homePopular : viewModel.featuredDramas
}
```

这会掩盖真实 API 空数据问题。Task27 Home/Rankings/Categories 要用真实接口数据联调，不能在真实模式下用 MockData 假装有数据。

## 责任判断

这次有两层问题：

1. Codex 的上一版任务书用英文写，不利于用户直接审阅，后续改为中文。
2. CC 没有严格按验收标准执行。尤其是接口 500、V7 未进 Flyway 这类硬失败，不应该标记“完成”。

## 下一步

不要提交 R4。进入 Task27 R5，只修阻塞项：

1. 修 Rankings 后端 500，API 必须 200 且有多条真实数据。
2. V7 必须由 Flyway 正常记录，不能手动导入后交付。
3. 修 Home 搜索栏顶部布局，不能重复叠加 safe area。
4. Categories 做成独立组件/模型，移除 HomeView 内硬编码筛选矩阵。
5. Task27 真实模式删除 Home/Rankings/Categories 的 MockData 兜底。
6. 交付报告必须写真实验证结果，失败项不能写“完成”。
