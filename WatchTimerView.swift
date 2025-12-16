import SwiftUI

struct WatchTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: TimerViewModel
    @State var monitor = SpeakingRateMonitor()

    init(totalSeconds: Int) {
        _vm = StateObject(
            wrappedValue: TimerViewModel(totalSeconds: totalSeconds)
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            // Top row
            HStack(spacing: 12) {
                waveformBadge
                    .frame(width: 58, height: 58)

                Text(vm.mmss)
                    .font(
                        .system(size: 22, weight: .semibold, design: .rounded)
                    )
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                vm.togglePause()
            } label: {
                Text(vm.isPaused ? "Resume" : "Pause")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(CapsuleFillStyle(fill: Color(.red)))
            .buttonStyle(CapsuleFillStyle(fill: Color.red.opacity(0.85)))
            
            .padding(.top, 30)

        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(Color.black)
    }

    // MARK: - Pieces

    private var waveformBadge: some View {
        ZStack {
            HStack{
                
                Text("\(monitor.currentWPM)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                // Colore del testo in base alla soglia
                    .foregroundColor(
                        monitor.currentWPM > monitor.wpmThreshold
                        && monitor.isMonitoring ? .red : .green
                    )
                Text("WPM")
                .font(.system(size: 12, weight: .light, design: .rounded))            }
        }

    }
}

struct CapsuleFillStyle: ButtonStyle {
    let fill: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Capsule())
            .background(
                Capsule()
                    .fill(fill)
                    .opacity(configuration.isPressed ? 0.7 : 1.0)
            )
    }
}

#Preview {
    WatchTimerView(totalSeconds: 122)
}
