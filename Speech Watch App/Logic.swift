//
//  Logic.swift
//  Speech Watch App
//
//  Created by Andreina Costagliola on 02/12/25.
//

import Foundation
import SwiftUI
import WatchKit
import AVFoundation
import Observation

@Observable
class SpeakingRateMonitor {
    
    //Observable parameters for UI
    var isMonitoring = false
    var currentWPM: Int = 0 // Words Per Minute (esteemed)
    var statusMessage: String = "Ready"
    
    //Max and Min WPM threshold
    let wpmThreshold: Int = 160
    let wpmThresholdMin: Int = 100
    
    //RMS: minimum amplitude of noise to be considered words and not external noise
    private var rmsThreshold: Float = 0.005 //REMEMBER TO INCREASE THIS NUMBER IF IT DETECTS TO MUCH NOISE
    

    private var audioEngine: AVAudioEngine?
    private var lastHapticTime: Date?
    private let hapticCooldown: TimeInterval = 3.0
    
    private var totalSpeakingTime: TimeInterval = 0.0
    private var totalMonitoringTime: TimeInterval = 0.0
    private let updateInterval: TimeInterval = 1.0
    private var calculationTimer: Timer?
    
    
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        //Microphone authorization
        Task {
            let authorized = await requestMicrophonePermission()
            
            if authorized {
                // 2. Esegui il setup e l'avvio sull'attore principale per gli aggiornamenti UI
                await MainActor.run {
                    self.statusMessage = "Starting..."
                    self.isMonitoring = true
                    self.resetMetrics()
                    self.setupAudioEngine()
                    self.startCalculationTimer()
                }
            } else {
                await MainActor.run {
                    self.statusMessage = "Permesso Microfono Negato. Controlla Impostazioni."
                    self.isMonitoring = false
                }
            }
        }
    }
    
    // -----------------------------------------------------
    // 2. Funzione Principale di Arresto
    // -----------------------------------------------------
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        statusMessage = "Pronto"
        
        // Invalida e rimuovi il timer di calcolo
        calculationTimer?.invalidate()
        calculationTimer = nil
        
        // Arresta e disconnetti l'audio engine
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            print("Monitoraggio e Audio Engine arrestati.")
        }
        
        resetMetrics()
    }
    
    // -----------------------------------------------------
    // 3. Logica di Setup e Gestione Permessi
    // -----------------------------------------------------
    
    private func requestMicrophonePermission() async -> Bool {
        let status = await AVAudioApplication.requestRecordPermission()
        return status
    }
    
    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        self.audioEngine = engine
        
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        // Installiamo il "tap" per l'analisi del segnale
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] (buffer, time) in
            // Processiamo il buffer nel thread ad alta priorità in cui viene chiamato il tap
            self?.processAudioBuffer(buffer: buffer)
        }
        
        do {
            try engine.start()
            print("AVAudioEngine avviato.")
            statusMessage = "In Monitoraggio..."
        } catch {
            print("Errore nell'avvio di AVAudioEngine: \(error.localizedDescription)")
            stopMonitoring()
            statusMessage = "Errore Audio"
        }
    }
    
    // -----------------------------------------------------
    // 4. Voice Activity Detection (VAD) - Analisi del Segnale
    // -----------------------------------------------------
    
    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let frameLength = buffer.frameLength
        let sampleRate = buffer.format.sampleRate
        
        // Calcolo dell'RMS (Root Mean Square) per misurare l'energia del suono
        var sumOfSquares: Float = 0.0
        for i in 0..<Int(frameLength) {
            let sample = data.pointee[i]
            sumOfSquares += sample * sample
        }
        
        let rms = sqrt(sumOfSquares / Float(frameLength))
        let bufferDuration = Double(frameLength) / sampleRate
        
        // Se l'RMS supera la soglia, registriamo che c'è attività vocale
        if rms > rmsThreshold {
            // Aggiungiamo la durata del buffer al tempo totale di parlato
            totalSpeakingTime += bufferDuration
        }
        
        // Aggiorna il tempo totale di monitoraggio
        totalMonitoringTime += bufferDuration
    }
    
    // -----------------------------------------------------
    // 5. Logica di Calcolo WPM e Timer
    // -----------------------------------------------------
    
    private func startCalculationTimer() {
        // Il timer si assicura che il calcolo WPM e l'aggiornamento UI avvengano a intervalli regolari
        calculationTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.calculateAndCheckRate()
        }
    }
    
    private func calculateAndCheckRate() {
        guard totalMonitoringTime > 0 else {
            statusMessage = "In Monitoraggio: \(Int(totalMonitoringTime))s"
            return
        }
        
        // 1. Calcola la Densità di Parlato (Speech Density: quanto tempo hai parlato rispetto al tempo totale)
        let speechDensity = totalSpeakingTime / totalMonitoringTime
        
        // 2. Mappa la densità WPM (Stima)
        // La mappatura è un'euristica: più alta è la densità, più veloce stai parlando.
        let minWPM: Int = 60
        let maxWPM: Int = 300
        
        let calculatedRate = Int(Float(minWPM) + (Float(maxWPM - minWPM) * Float(speechDensity)))
        
        // 3. Aggiorna lo stato su MainActor
        DispatchQueue.main.async {
            self.currentWPM = calculatedRate
            self.checkThreshold()
        }
    }
    
    private func resetMetrics() {
        totalSpeakingTime = 0.0
        totalMonitoringTime = 0.0
        currentWPM = 0
        lastHapticTime = nil
    }
    
    // -----------------------------------------------------
    // 6. Logica di Soglia e Haptic Feedback
    // -----------------------------------------------------
    
    private func checkThreshold() {
        if currentWPM > wpmThreshold {
            triggerHapticFeedback()
            statusMessage = "🚨 VELOCITÀ ECCESSIVA! Rallenta."
        } else if isMonitoring {
            statusMessage = "In Monitoraggio: Tutto OK"
        }
    }
    
    private func triggerHapticFeedback() {
        let now = Date()
        // Controllo di Cooldown
        if let lastTime = lastHapticTime, now.timeIntervalSince(lastTime) < hapticCooldown {
            return
        }
        
        // Esegue la vibrazione
        WKInterfaceDevice.current().play(.notification)
        print("VIBRAZIONE: Soglia \(wpmThreshold) WPM superata (\(currentWPM) WPM).")
        lastHapticTime = now
    }
}
