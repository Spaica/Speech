import SwiftUI

struct TimerSetUpView: View {
    // Stato per la selezione del tempo
    @State private var minutes = 2
    @State private var seconds = 0
    
    // Lo stato che guida la navigazione
    @State private var navigateToRecording = false
    @State private var selectedDuration = 0
    
    // Inizializza il monitor rateMonitor solo una volta
    @State private var rateMonitor = SpeakingRateMonitor()

    var body: some View {
        VStack {
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

                VStack(spacing: -10) {
                    Picker("Seconds", selection: $seconds) {
                        ForEach(0..<60) { Text("\($0)").tag($0) }
                    }
                    .frame(width: 60, height: 80)
                    .labelsHidden()
                }
            }

            Spacer()

            // PULSANTE START
            Button {
                // 1. Calcola la durata
                let totalSeconds = minutes * 60 + seconds
                guard totalSeconds > 0 else { return }
                
                // 2. Imposta lo stato e attiva la navigazione
                selectedDuration = totalSeconds
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

                    Text("Start")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(minutes == 0 && seconds == 0)
        }
        // DESTINAZIONE DI NAVIGAZIONE
        .navigationDestination(isPresented: $navigateToRecording) {
            // Passa la durata e il monitor alla vista successiva
            WatchTimerView(totalSeconds: selectedDuration, rateMonitor: rateMonitor)
        }
    }
}

#Preview {
    // Avvolgi in NavigationStack per il preview
    NavigationStack {
        TimerSetUpView()
    }
}
