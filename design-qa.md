# Help & Feedback Product Design QA

## Evidence

- Source visual truth: `/var/folders/24/hnnvyxbn1s13bt4bjv9bl4m40000gn/T/codex-clipboard-3ba638a4-76d1-47a7-bbd1-431e56d01816.png`
- Final help center: `/tmp/relaxshort-support-1to1-qa/help-final.png`
- VIP common-question menu: `/tmp/relaxshort-support-1to1-qa/vip-dropdown.png`
- Combined comparison: `/tmp/relaxshort-support-1to1-qa/design-comparison.png`
- Viewport: iPhone 17 Simulator, 402 × 874 pt, dark mode, Simplified Chinese.
- Source pixels: 1342 × 1310 composite image.
- Implementation pixels: 1206 × 2622 at 3× density.
- The source help-center panel was cropped and normalized to the same 402 × 874 visual slot as the implementation.

## State and comparison scope

- The source contains seeded ticket rows while the local simulator has no tickets. Ticket-list data was not treated as a visual defect.
- The comparison covers navigation, search, the three quick-category entries, CTA, ticket-section hierarchy, spacing, typography, icon shape, and color.
- The VIP issue is intentionally placed in the common-question menu rather than compressing the three source category columns into four.

## Comparison history

1. The previous implementation approximated all three category graphics with SF Symbols.
   - Finding: P2 icon-shape and color drift, especially for playback/download and the coin stack.
2. Replaced the three approximations with tightly cropped assets extracted from the supplied source visual.
   - Increased the icon presentation area and category-card height to match the source proportions.
   - Confirmed there are no visible raster-background seams against the dark category card.
3. The previous support flow used the global coral red `#E85048`.
   - Finding: P2 color drift from the supplied support design.
   - Scoped the support flow to the source-sampled deep red `#DA1D20`, including the CTA, status color, message accents, and send controls.
4. Added an accessible common-question menu to the search bar.
   - The menu contains playback, coins, VIP activation, and sign-in issues.
   - Selecting the VIP entry filters directly to “购买 VIP 后没有到账”.

## Required fidelity surfaces

- Typography: system weights and Chinese labels match the selected design hierarchy without clipping.
- Spacing: search, category card, CTA, and ticket heading follow the source rhythm and safe-area behavior.
- Colors: category graphics preserve their source gold; the support-specific red is sampled from the supplied visual; dark panels, grey borders, and white text are aligned.
- Image and icon quality: the three quick-category icons use the supplied source artwork at 3× density instead of unrelated system-symbol substitutes.
- Copy and content: the VIP purchase-not-activated FAQ exists in all eight localization files and is reachable from the common-question menu and direct search.

## Interaction checks

- Profile → Help & Feedback: passed.
- Common questions → VIP purchase not activated: passed.
- Empty ticket state: passed.
- Live ticket creation and server reply: not run because the backend was intentionally not started.

## Verification

- `xcodebuild -quiet -project RelaxShort.xcodeproj -scheme RelaxShort -configuration Debug -destination 'platform=iOS Simulator,id=99782FD0-C497-439F-B95E-949E6AB85F1C' build`
- Result: `BUILD SUCCEEDED`

final result: passed

---

# Offline Downloads Product Design QA

## Evidence

- Selected visual truth: `/Users/ethan/.codex/generated_images/019f79a3-b347-7671-ab45-21c816edd61d/call_YeRTh1YZyKMj6hbx0a3URufb.png`
- Final download page: `/tmp/relaxshort-downloads-qa/downloads-final.png`
- Combined comparison: `/tmp/relaxshort-downloads-qa/downloads-comparison.png`
- Offline playback proof: `/tmp/relaxshort-downloads-qa/offline-playback.png`
- Viewport: iPhone 17 Simulator, 402 × 874 pt, dark mode, Simplified Chinese.

## Comparison scope

- Compared navigation, storage hierarchy, progress treatment, section titles, row density, typography, dark palette, and red/gold accents against the selected option.
- The selected visual contains three seeded dramas and an active queue item. The functional QA state contains one completed local video, so data quantity was not treated as a layout defect.
- No P0 or P1 visual defects were found. The empty cover in QA is expected because the local fixture intentionally has no remote artwork.

## Interaction checks

- Profile → Offline Downloads: passed.
- Completed download → offline player: passed.
- Local MP4 was opened by the shared `PlayerCoordinator` without the former missing-environment crash: passed.
- Edge-back from offline player: passed.

## Verification

- `xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/relaxshort-downloads-derived CODE_SIGNING_ALLOWED=NO build`
- Result: `BUILD SUCCEEDED`

final result: passed

---

# 播放器控制面板 Design QA

日期：2026-08-12
结论：**通过（模拟器视觉与交互 QA）**

## 对照输入

- 选定设计稿：`/Users/ethan/myspance/relaxshort/docs/design/player-controls/2026-08-12/option-1-cinematic-precision.png`
- 实现截图：`/Users/ethan/myspance/relaxshort/docs/launch-audit/screenshots/player-settings-after-2026-08-12.png`（最终版移除分段 Tab，保留同一套三组控制并扩大默认高度）
- 分享截图：`/Users/ethan/myspance/relaxshort/docs/launch-audit/screenshots/player-share-after-2026-08-12.png`
- 设备/视口：iPhone 15 Pro，iOS 17.0，1179×2556

## 可见差异检查

- [x] 深色全宽底部面板、24pt 圆角、顶部拖拽条与设计方向一致。
- [x] 倍速为一行六档，选中态使用 Logo 红，没有遗留粉色。
- [x] Auto、标准清晰度、1080P VIP 锁定的视觉层级与设计一致。
- [x] 字幕与倍速、清晰度收口到同一播放设置面板，不再维护多套弹窗。
- [x] 分享面板沿用同一深色、圆角、Logo 红和次级卡片系统。
- [x] 关闭按钮、锁图标、勾选态、文字对比度和触控区域无明显裁切。
- [x] 英文长文案可容纳；内容超出首档高度时可滚动。
- [x] 真实后端清晰度为 540P/720P/1080P，因此实现使用 540P 替代设计示意中的 480P。

## 交互检查

- [x] 顶部 Speed 与更多按钮打开同一个播放设置组件。
- [x] 倍速、画质、字幕均可操作；可选项选择后关闭面板。
- [x] 非 VIP 点击 1080P 进入会员路径，且后端不返回该直链。
- [x] 分享、复制链接保留原业务回调。

## 尚需外部验收

- [ ] 真实 iPhone 上检查 Dynamic Type、VoiceOver、阿语 RTL 和横竖屏。
- [ ] 部署 V59 并用真实 HLS/CDN 验证 720P/1080P Auto、手动固定档和弱网切档。
- [ ] 用 Instruments/线上监控采集 P50/P90/P95 首帧耗时；模拟器截图不能证明“秒开”。
