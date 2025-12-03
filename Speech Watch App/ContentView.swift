//
//  ContentView.swift
//  Speech Watch App
//
//  Created by Andreina Costagliola on 02/12/25.
//

import SwiftUI

struct ContentView: View {
    
    @State var monitor = SpeakingRateMonitor()
    
    var body: some View {
        VStack(spacing: 8) {
            
            // Messaggio di Stato
            Text(monitor.statusMessage)
                .font(.caption)
                .foregroundColor(monitor.currentWPM > monitor.wpmThreshold && monitor.isMonitoring ? .red : .gray)
                .padding(.top, 4)
            
            // Velocità WPM
            VStack {
                Text("\(monitor.currentWPM)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    // Colore del testo in base alla soglia
                    .foregroundColor(monitor.currentWPM > monitor.wpmThreshold && monitor.isMonitoring ? .red : .green)
                
                Text("WPM (stimato)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.vertical, 4)
            
            Spacer()
            
            // Bottone di Controllo principale
            Button(action: {
                if monitor.isMonitoring {
                    monitor.stopMonitoring()
                } else {
                    monitor.startMonitoring()
                }
            }) {
                Text(monitor.isMonitoring ? "STOP" : "INIZIA")
                    .bold()
            }
            .padding()
            // Cambia colore del bottone per feedback visivo
            .background(monitor.isMonitoring ? Color.red : Color.green)
            .cornerRadius(12)
            .buttonStyle(.borderedProminent)
        }
        .padding()
        // Assicurati di fermare il monitoraggio quando l'utente esce dalla vista
        .onDisappear {
            monitor.stopMonitoring()
        }
    }
}

#Preview {
    ContentView()
}
