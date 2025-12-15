//
//  WatchTimerView.swift
//  Speech Watch App
//
//  Created by Andreina Costagliola on 15/12/25.
//

import SwiftUI

struct WatchTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: TimerViewModel
    // Aggiungi il monitor come ObservableObject
    // Assumiamo che SpeakingRateMonitor sia marcato con @Observable (o ObservableObject)
    @State var rateMonitor: SpeakingRateMonitor

    init(totalSeconds: Int, rateMonitor: SpeakingRateMonitor) {
        _vm = StateObject(
            wrappedValue: TimerViewModel(totalSeconds: totalSeconds)
        )
        // Assegna il monitor
        _rateMonitor = State(initialValue: rateMonitor)
    }
    
    // MARK: - Computed Properties for Display
    
    // Logica per il messaggio di stato: Ready -> Monitoring... -> Slow down!
    private var displayStatus: String {
        // Ho integrato la logica per mostrare "Monitoring..." quando lo stato è "OK" (che è il messaggio di default quando non c'è Slow Down)
        if rateMonitor.statusMessage == "Slow down!" {
            return "Slow down!" // Quando supera la soglia (prioritario)
        } else if rateMonitor.isMonitoring {
            return "Monitoring..." // Stato generale di monitoraggio (anche se il messaggio è "OK")
        } else {
            return "Ready" // Stato iniziale o di pausa/stop
        }
    }
    
    // Colore per lo stato
    private var statusColor: Color {
        if rateMonitor.statusMessage == "Slow down!" {
            return .red
        } else if rateMonitor.isMonitoring {
            return .green
        } else {
            return .gray
        }
    }


    var body: some View {
        // Uso un VStack principale senza spaziatura rigida per massimizzare lo spazio sullo schermo dell'Apple Watch
        VStack {
            VStack(spacing: 0) {
                
                // TOP ROW: Waveform and Status Message
                HStack(spacing: 2) {
                    waveformBadge
                        .frame(width: 58, height: 48)
                        .padding(.leading, 25)
                    
                    // Messaggio di Stato
                    VStack(alignment: .leading) {
                        Text(displayStatus) // Usa la computed property per la stringa desiderata
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(statusColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Ho rimosso questo Text che non era presente nella tua ultima versione
                        /*
                        Text("Speech Rate Status")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                         */
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4) // Mantengo un po' di spazio in cima

                // TIMER MM:SS
                Text(vm.mmss)
                    .font(
                        .system(size: 28, weight: .semibold, design: .rounded)
                    )
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4) // Ridotto il padding verticale per compattare
                    .background(.ultraThinMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            // Aggiungo uno Spacer per spingere i bottoni in basso
            Spacer()

            // WPM INSTANTANEOUS DISPLAY (Lo sposto sopra i bottoni)
            VStack(spacing: 2) {
                Text("\(rateMonitor.currentWPM)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    // Colore del WPM istantaneo
                    .foregroundColor(rateMonitor.currentWPM > rateMonitor.wpmThreshold && rateMonitor.isMonitoring ? .red : .green)
                
                Text("WPM (Rate)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 8) // Separazione tra WPM e il bottone

            // MARK: - CONTROL BUTTONS
            
            // Pulsante PAUSE / RESUME
            Button {
                vm.togglePause()
                // Ferma/Riprendi monitoraggio con la pausa del timer
                if vm.isPaused {
                    rateMonitor.stopMonitoring()
                } else {
                    rateMonitor.startMonitoring()
                }
            } label: {
                Text(vm.isPaused ? "Resume" : "Pause")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            // LOGICA COLORE: ROSSO se in PAUSA (mostra "Pause"), GRIGIO se in RESUME (mostra "Resume")
            .buttonStyle(
                CapsuleFillStyle(
                    fill: vm.isPaused ? Color(.gray) : Color.red.opacity(0.85) // Invertito il colore come richiesto
                )
            )
            // Aggiungo un pulsante Stop opzionale se la tua UI lo richiede, ma lo lascio commentato
            /*
            Button(role: .destructive) {
                vm.stop()
                rateMonitor.stopMonitoring()
                dismiss()
            } label: {
                Text("Stop")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(CapsuleFillStyle(fill: Color.red.opacity(0.6)))
            */
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8) // Padding dal basso
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(Color.black)
        .onAppear {
            vm.start()
            rateMonitor.startMonitoring()
        }
        .onDisappear {
            rateMonitor.stopMonitoring()
        }
        .onChange(of: vm.remaining) { _, newRemaining in
            if newRemaining == 0 {
                rateMonitor.stopMonitoring()
            }
        }
    }

    // MARK: - Pieces (non modificato)
    private var waveformBadge: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.85), Color.cyan.opacity(0.55),
                        ]),
                        center: .center,
                        startRadius: 2,
                        endRadius: 40
                    )
                )

            Image(systemName: "waveform.circle")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.white)
                .blendMode(.overlay)
                .opacity(0.95)
        }
        .overlay(
            Circle().stroke(.white.opacity(0.9), lineWidth: 1.2)
        )
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
    WatchTimerView(totalSeconds: 122, rateMonitor: SpeakingRateMonitor())
        .previewDevice("Apple Watch Series 9 (45mm)")
}
