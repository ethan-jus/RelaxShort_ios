import SwiftUI
import Combine

// MARK: - BannerCarousel ViewModel

/// Banner 轮播 ViewModel — 管理轮播索引和自动播放
@MainActor
final class BannerCarouselViewModel: ObservableObject {
    @Published var currentIndex: Int = 0
    @Published var isAutoScrolling: Bool = true

    private var timer: AnyCancellable?
    private var itemCount: Int = 0
    private let autoScrollInterval: TimeInterval

    init(autoScrollInterval: TimeInterval = 3.0) {
        self.autoScrollInterval = autoScrollInterval
    }

    func startAutoScroll(itemCount: Int) {
        self.itemCount = itemCount
        guard itemCount > 1 else { return }
        isAutoScrolling = true
        timer?.cancel()
        timer = Timer.publish(every: autoScrollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    self.currentIndex = (self.currentIndex + 1) % self.itemCount
                }
            }
    }

    func stopAutoScroll() {
        isAutoScrolling = false
        timer?.cancel()
    }



    /// 手动翻页
    func goToNext() {
        guard itemCount > 0 else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            currentIndex = (currentIndex + 1) % itemCount
        }
    }

    func goToPrevious() {
        guard itemCount > 0 else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            currentIndex = (currentIndex - 1 + itemCount) % itemCount
        }
    }
}
