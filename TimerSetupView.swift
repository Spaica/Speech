import SwiftUI

struct TimerSetupView: View {
    @State private var minutes = 0
    @State private var seconds = 1
    @State private var navigateToRecording = false
    @State private var selectedDuration = 0

    var body: some View {
        VStack(spacing: -5) {
            // Time pickers
            HStack(spacing: 10) {
                VStack(spacing: -10) {
                    Picker("Minutes", selection: $minutes) {
                        ForEach(0..<60) { Text("\($0)").tag($0) }
                    }
                    .frame(width: 60, height: 80)
                    .labelsHidden()
                    
                }

                Text(":")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                VStack {
                    Picker("Seconds", selection: $seconds) {
                        ForEach(0..<60) { Text("\($0)").tag($0) }
                    }
                    .frame(width: 60, height: 80)
                    .labelsHidden()
                    
                }
            }
            .padding(10)
            Spacer()

            Button {
                guard minutes > 0 || seconds > 0 else { return }
                selectedDuration = minutes * 60 + seconds
                navigateToRecording = true
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan, Color.blue.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 80, height: 80)
                        .padding(10)

                    Text("Start")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                
            }
            .buttonStyle(.plain)
            .disabled(minutes == 0 && seconds == 0)

        }

            .navigationDestination(isPresented: $navigateToRecording) {
                WatchTimerView(totalSeconds: selectedDuration)
            }
    }
}
