import Foundation
import Combine

final class TimerViewModel: ObservableObject {
    @Published var remaining: Int
    @Published var isPaused: Bool = false

    private var timerCancellable: AnyCancellable?

    init(totalSeconds: Int) {
        self.remaining = max(0, totalSeconds)
        start()
    }

    func start() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard !self.isPaused else { return }
                if self.remaining > 0 { self.remaining -= 1 }
            }
    }

    func togglePause() { isPaused.toggle() }

    func stop() {
        remaining = 0
        isPaused = true
    }

    var mmss: String {
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }
}
