import Foundation
import SwiftUI

// MARK: - 竖屏视频分页器

/// For You 与 Series 共享的分页交互状态。
///
/// 页面只读取这里的拖拽位移；播放器、锁集、推荐分页等业务仍由各自页面持有，
/// 避免通用手势组件反向依赖播放状态机。
@MainActor
final class VerticalVideoPagerState: ObservableObject {
    @Published fileprivate(set) var dragOffset: CGFloat = 0
    @Published private(set) var isDragging = false

    private var gestureGeneration = 0

    fileprivate func beginDragging() {
        gestureGeneration &+= 1
        isDragging = true
    }

    fileprivate func updateDrag(
        translation: CGFloat,
        currentIndex: Int,
        pageCount: Int,
        edgeResistance: CGFloat
    ) {
        let atFirstPage = currentIndex == 0 && translation > 0
        let atLastPage = currentIndex == pageCount - 1 && translation < 0
        dragOffset = atFirstPage || atLastPage
            ? translation * edgeResistance
            : translation
    }

    fileprivate func resetOffset() {
        dragOffset = 0
    }

    fileprivate func finishDragging(after duration: TimeInterval) {
        let generation = gestureGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self, self.gestureGeneration == generation else { return }
            self.isDragging = false
        }
    }
}

/// 三页窗口分页布局。只创建当前页及相邻页，避免长 Feed 同时构建大量视频视图。
struct VerticalVideoPager<Page: View>: View {
    @ObservedObject var state: VerticalVideoPagerState
    let pageCount: Int
    let currentIndex: Int
    let pageHeight: (GeometryProxy) -> CGFloat
    let page: (_ index: Int, _ isCurrent: Bool) -> Page

    init(
        state: VerticalVideoPagerState,
        pageCount: Int,
        currentIndex: Int,
        pageHeight: @escaping (GeometryProxy) -> CGFloat = { $0.size.height },
        @ViewBuilder page: @escaping (_ index: Int, _ isCurrent: Bool) -> Page
    ) {
        self.state = state
        self.pageCount = pageCount
        self.currentIndex = currentIndex
        self.pageHeight = pageHeight
        self.page = page
    }

    var body: some View {
        GeometryReader { geo in
            let height = max(1, pageHeight(geo))
            let safeIndex = clampedIndex
            let yOffset = -CGFloat(safeIndex) * height + state.dragOffset

            ZStack {
                ForEach(visibleIndices(around: safeIndex), id: \.self) { index in
                    page(index, index == safeIndex)
                        .frame(width: geo.size.width, height: height)
                        .position(
                            x: geo.size.width / 2,
                            y: CGFloat(index) * height + height / 2 + yOffset
                        )
                }
            }
            .frame(width: geo.size.width, height: height)
            .clipped()
        }
    }

    private var clampedIndex: Int {
        guard pageCount > 0 else { return 0 }
        return max(0, min(currentIndex, pageCount - 1))
    }

    private func visibleIndices(around index: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        return Array(max(0, index - 1)...min(pageCount - 1, index + 1))
    }
}

/// 统一竖屏分页手势：跟手拖动、方向判断、速度翻页、首尾阻尼和原子回弹。
private struct VerticalVideoPagingModifier: ViewModifier {
    @ObservedObject var state: VerticalVideoPagerState
    let pageCount: Int
    let currentIndex: Int
    let canHandle: (DragGesture.Value) -> Bool
    let onPageCommit: (_ from: Int, _ to: Int) -> Bool

    private let minimumDistance: CGFloat = 10
    private let distanceThreshold: CGFloat = 80
    private let velocityThreshold: CGFloat = 300
    private let edgeResistance: CGFloat = 0.4
    private let verticalDominance: CGFloat = 1.2
    private let animationDuration: TimeInterval = 0.35

    func body(content: Content) -> some View {
        content.simultaneousGesture(pagingGesture)
    }

    private var pagingGesture: some Gesture {
        DragGesture(minimumDistance: minimumDistance)
            .onChanged { value in
                guard pageCount > 0, accepts(value) else { return }
                state.beginDragging()
                state.updateDrag(
                    translation: value.translation.height,
                    currentIndex: safeCurrentIndex,
                    pageCount: pageCount,
                    edgeResistance: edgeResistance
                )
            }
            .onEnded { value in
                guard pageCount > 0, state.isDragging, accepts(value) else {
                    settleWithoutTransition()
                    return
                }

                let oldIndex = safeCurrentIndex
                let targetIndex = resolvedTarget(from: oldIndex, value: value)

                // 业务层同步提交 selection，与 dragOffset 归零处于同一个动画事务，
                // 保证旧页连续滑出、新页连续滑入；提交失败时则自然回弹。
                withAnimation(.spring(response: animationDuration, dampingFraction: 0.82)) {
                    if targetIndex != oldIndex {
                        _ = onPageCommit(oldIndex, targetIndex)
                    }
                    state.resetOffset()
                }
                state.finishDragging(after: animationDuration)
            }
    }

    private var safeCurrentIndex: Int {
        max(0, min(currentIndex, pageCount - 1))
    }

    private func accepts(_ value: DragGesture.Value) -> Bool {
        guard canHandle(value) else { return false }
        return abs(value.translation.height) > abs(value.translation.width) * verticalDominance
    }

    private func resolvedTarget(from oldIndex: Int, value: DragGesture.Value) -> Int {
        let velocity = value.predictedEndTranslation.height - value.translation.height
        if value.translation.height < -distanceThreshold || velocity < -velocityThreshold {
            return min(oldIndex + 1, pageCount - 1)
        }
        if value.translation.height > distanceThreshold || velocity > velocityThreshold {
            return max(oldIndex - 1, 0)
        }
        return oldIndex
    }

    private func settleWithoutTransition() {
        withAnimation(.spring(response: animationDuration, dampingFraction: 0.82)) {
            state.resetOffset()
        }
        state.finishDragging(after: animationDuration)
    }
}

extension View {
    /// 将统一的竖屏分页手势挂到实际交互层；页面内容与手势层可以分离。
    func verticalVideoPaging(
        state: VerticalVideoPagerState,
        pageCount: Int,
        currentIndex: Int,
        canHandle: @escaping (DragGesture.Value) -> Bool = { _ in true },
        onPageCommit: @escaping (_ from: Int, _ to: Int) -> Bool
    ) -> some View {
        modifier(
            VerticalVideoPagingModifier(
                state: state,
                pageCount: pageCount,
                currentIndex: currentIndex,
                canHandle: canHandle,
                onPageCommit: onPageCommit
            )
        )
    }
}
