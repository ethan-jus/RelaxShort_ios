# Home 卡片角标设计

## 目标

修正 Popular、VIP、Original+ 三个 Tab 的角标语义和样式。剧集播放权限与栏目运营角标必须分离，客户端不得根据 `vip_required` 在所有 Home 页面自动显示 VIP。

## 数据职责

- `monetization.vip_required`：剧集权益数据，只控制播放、解锁和会员拦截。
- `display_flags`：内容自身的长期属性，例如 `AI`，不承担栏目投放状态。
- `placement_badge`：Home 栏目条目级运营角标。同一部剧在不同 section 中可配置不同值。

后端在 `rs_home_section_items` 增加可选的投放角标配置，并在 Home API 的每个卡片中返回结构化 `placement_badge`。标准类型为 `hot`、`new`、`following`、`members_only`，同时保留自定义文案能力。

## 页面规则

- Popular：仅展示 `placement_badge`，禁止由 `vip_required` 自动生成 VIP 角标。
- VIP：栏目数据必须是会员内容，卡片统一返回并展示 `members_only`。
- Original+：仅展示 `hot`、`new`、`following` 或自定义运营角标，禁止显示 `members_only`。
- 播放权限始终按真实 `vip_required` 执行，隐藏 Home 角标不改变权限。

## iOS 设计

- DTO、Repository 和 `DramaItem` 增加可选的结构化投放角标。
- Home 卡片统一使用一个角标组件，不再分别拼装 `VIP`、`Members Only` 和 `displayFlags.first`。
- `Members Only` 使用浅金底和深金文字；`Hot` 使用品牌红；`New`、`Following` 使用克制的紫色；自定义类型使用中性样式。
- 角标贴合封面右上角，圆角和卡片规范一致，不增加改变卡片尺寸的外边距。

## 后端修正

- 新建后续 Flyway migration，不修改已执行的 V11/V12。
- 清理本地开发数据中错误展示的 `Test` 投放角标。
- V12 对共享 feed snapshot 写入 VIP 状态属于错误职责，后续迁移恢复由真实剧集/剧集集数权益决定的 monetization。
- VIP section 只配置真实会员内容；section 配置不能反向污染同一剧在其他 Tab 的卡片快照。

## 验收

- Popular 不出现通用 `VIP` 标签。
- VIP 每张卡片均显示 `Members Only`，且点击后的权限行为与接口一致。
- Original+ 不出现 `Members Only`，可按 section 配置显示运营角标。
- 同一剧在三个 Tab 的角标可不同，播放权限保持一致。
- 后端测试、Flyway 校验和 iOS 多尺寸构建通过。
