# Task31 My List 视觉合同

本文是 CC 实现 My List UI 的唯一视觉输入。CC 不需要、也不得声称自己识别了参考截图；Codex 已检查截图并把可执行要求写在这里。

## 参考来源

- 普通态：`/Users/ethan/myspance/relaxshort/design-reference/dramabox/05_mylist/mylist_不要预约功能.JPG`
- 编辑态：`/Users/ethan/myspance/relaxshort/design-reference/dramabox/05_mylist/右侧编辑按钮的页面.PNG`

参考图中的 `Reminder Set` 明确不做。页面只保留 `Following` 和 `History`，其中 `Following` 的真实业务状态是 bookmark，不调用 follow API。

## 当前实现与目标的关键差异

当前 `FavoritesView` 使用圆角卡片容器、面板背景、右箭头、固定封面尺寸和 `MockData`。目标页面是黑色平面列表，没有卡片背景、列表外框和右箭头。当前页面还缺少编辑多选、底部 Remove 栏、真实分页、真实历史续播和真实 Most Trending。

实现时禁止在现有 UI 上继续叠加偏移和补丁。需要先建立一套明确的页面、列表行和底部栏布局合同。

## 普通态页面结构

### 页面背景与安全区

- 页面背景为纯黑，覆盖全屏。
- 顶部内容从系统安全区下方开始，不额外显示 `My List` 导航标题。
- 底部滚动内容必须避开自定义主 Tab Bar，只有一个底部避让来源。
- 使用实际容器宽度和 safe area；禁止按设备型号分支。

### 顶部页签

- 左侧依次显示 `Following`、`History`，右侧显示 `slider.horizontal.3` 编辑按钮。
- 不显示 `Reminder Set`。
- 顶部水平边距 16pt；页签和编辑按钮共享一行。
- 页签字号约 20pt，选中项 semibold/白色，未选中项 regular/约 55% 白色。
- 选中项下方为短横线，宽约 28pt、高 3pt、圆角，颜色使用 `DB.logoRed`。
- 编辑按钮点击区域至少 44×44pt，图标保持白色。

### Following 与 History 列表行

- 行是透明背景，不使用卡片底色、描边、阴影或 chevron。
- 行水平边距 16pt，普通态海报左侧与页面边距对齐。
- 行内海报固定 2:3 比例；宽度按容器计算：

```swift
let coverWidth = min(max(containerWidth * 0.22, 72), 92)
let coverHeight = coverWidth * 1.5
```

- 海报圆角只使用 `DB.posterRadius`，禁止新增更大的局部圆角。
- 海报和文字区间距 14–16pt。
- 相邻行垂直间距约 18–20pt。
- 海报底边覆盖一条 3pt 高的进度线：底轨为约 25% 白色，已观看部分使用 `DB.logoRed`。进度限制在 `0...1`。
- 对没有观看进度的收藏项，红色进度可以为 0，但底轨仍保持稳定，不允许整行跳动。

文字区从上到下：

1. 标题：17pt semibold、白色、单行截断。
2. 标签：15pt regular、约 45% 白色、单行截断。使用后端 category/region/language 可用字段组合，不显示空分隔符。
3. 集数：16pt regular、约 60% 白色，格式为 `EP.{current} / EP.{total}`。

Following 没有历史进度时，`current` 使用可播放入口的集数，默认 1；History 必须使用后端 `episode_number`，不能通过数组下标推断。

### 点击行为

- Following 行点击进入对应短剧播放页，从服务端可播放入口开始；如已有该短剧历史进度，可使用真实续播信息。
- History 行点击必须携带真实 `episode_id`、`episode_number` 和 `resume_time`，进入用户实际观看的单集。
- 分页加载触发区不能和行点击冲突。

## Most Trending

- Following/History 列表之后显示 `Most Trending`，顶部留约 32pt。
- 标题 20pt semibold、白色、左对齐，不添加彩色竖线。
- 使用真实 `type=trending` 排行数据，不读取 `MockData`。
- 三列自适应网格，水平边距 16pt，列间距 10pt，行间距约 18pt。
- 单卡海报保持项目统一海报比例和 `DB.posterRadius`。
- 海报左上角可复用当前排名角标；标题 14pt、最多两行，副标签 13pt、单行、灰色。
- 空榜、加载失败和分页结束必须有明确状态，不用 Mock 内容补位。

## 编辑态

编辑态只作用于 Following：

- 顶部页签行替换为居中的 `Choose` 和右侧 `Cancel`；`Cancel` 点击后退出编辑并清空选择。
- 隐藏主 Tab Bar，避免和 Remove 栏重叠。
- 每行左侧增加选择圆，圆心和海报垂直中心对齐。
- 选择圆占位宽度固定，保证所有海报左边缘一致。
- 未选中：白色 2pt 描边、内部透明/黑色。
- 已选中：`DB.logoRed` 实心圆和白色 checkmark。
- 已选中海报叠加约 45% 黑色遮罩；文字不变暗。
- 点击选择圆或整行选择区域切换选中状态，不能导航到播放器。

底部 Remove 栏：

- 固定在底部安全区之上，背景纯黑，顶部 0.5pt 分隔线。
- 高度为内容 56pt 加底部 safe area，只由该栏消费 safe area。
- 右侧显示 trash 图标和本地化 `Remove`，点击区域至少 44pt。
- 无选中项时禁用并降低透明度；有选中项时为白色。
- 删除过程中防止重复提交。
- 部分删除失败时，成功项立即消失，失败项保持选择，并只显示一条汇总错误。

## 加载、错误与空态

- Following、History、Most Trending 分别维护加载和错误状态，切换页签不能清空另一个页签已加载内容。
- 首屏加载使用居中 `ProgressView`，颜色 `DB.logoRed`。
- 已有内容的下一页加载只在列表底部显示小型进度，不遮盖整页。
- 错误态显示本地化错误文字和 `Retry`。
- Following 空态和 History 空态不显示 Mock 项目。
- 未登录继续沿用现有登录引导，但不能先闪出真实/Mock 列表。

## 本地化与无障碍

- 必须补齐 `en`、`zh-Hans`、`zh-Hant`、`es`、`pt`、`ja`、`ko`、`ar`。
- 阿拉伯语使用系统布局方向；不要手工反转数组或写死左右偏移。
- 顶部页签、编辑、取消、移除、Retry、空态和 Most Trending 均使用本地化键。
- 选择圆要提供 selected/unselected accessibility value；Remove 要说明当前选择数量。
- Dynamic Type 至少保证标题和操作不互相遮挡；必要时对顶部操作使用缩放下限而不是固定裁剪。

## 响应式验收

必须验证：

- 小屏：iPhone SE (3rd generation), iOS 17.0。
- 标准屏：iPhone 17。
- 大屏：iPhone 17 Pro Max。

每种尺寸检查：

- 标题、标签、集数不与海报或编辑圆重叠。
- 三列网格不越界。
- Remove 栏和主 Tab Bar 不同时出现。
- 最后一行能滚动到 Remove 栏或主 Tab Bar 上方。
- 长英文、中文和阿拉伯语文案不溢出。

## Codex 视觉复审要求

CC 完成后只需提供可运行构建和状态说明。Codex 负责在相同页面状态下截图，并与两张参考图对照检查：

- 页面层级和黑底平面感。
- 顶部页签和编辑入口。
- 海报尺寸、行距、文字层级和进度线。
- 编辑选择圆、海报遮罩和 Remove 栏。
- 小屏、标准屏和大屏安全区。

