//
//  Logic.swift
//  Speech Watch App
//
//  Created by The Sacrificers on 02/12/25.
//

import Foundation
import SwiftUI
import WatchKit
import AVFoundation
import Observation

// MARK: - CLASS SPEAKINGRATEMONITOR
/// Monitors speaking rate in real-time using audio input from the device microphone
/// Provides haptic feedback when speaking rate exceeds or falls below defined thresholds
@Observable
class SpeakingRateMonitor {
    
    // MARK: - Observable UI Parameters
    /// Indicates whether monitoring is currently active
    var isMonitoring = false
    
    /// Current estimated Words Per Minute
    var currentWPM: Int = 0
    
    /// Status message displayed to the user
    var statusMessage: String = "Ready"
    
    // MARK: - WPM Thresholds
    /// Maximum WPM threshold - triggers haptic feedback when exceeded
    let wpmThreshold: Int = 130
    
    /// Minimum WPM threshold - alerts user to speak faster
    let wpmThresholdMin: Int = 80
    
    // MARK: - Audio Detection Parameters
    /// Root Mean Square (RMS) threshold - minimum amplitude to consider audio as speech vs. noise
    /// Higher values = less sensitive to background noise
    private var rmsThreshold: Float = 0.05
    
    /// Peak amplitude threshold for detecting human voice (closer/louder sounds)
    /// Helps distinguish speech from constant background noise
    private var peakThreshold: Float = 0.08
    
    /// Number of consecutive silence frames required to consider a pause
    private var silenceFramesRequired: Int = 10
    
    /// Counter for consecutive silence frames
    private var currentSilenceFrames: Int = 0

    // MARK: - Audio Engine & Haptics
    /// Audio engine for processing microphone input
    private var audioEngine: AVAudioEngine?
    
    /// Timestamp of last haptic feedback to implement cooldown
    private var lastHapticTime: Date?
    
    /// Cooldown period between haptic feedback triggers (in seconds)
    private let hapticCooldown: TimeInterval = 2.0
    
    // MARK: - Calculation Variables
    /// Total time spent speaking (voice detected) in current interval
    private var totalSpeakingTime: TimeInterval = 0.0
    
    /// Total monitoring time in current interval
    private var totalMonitoringTime: TimeInterval = 0.0
    
    /// Interval for WPM calculation updates (in seconds)
    private let updateInterval: TimeInterval = 1.0
    
    /// Timer for periodic WPM calculations
    private var calculationTimer: Timer?
    
    /// Smoothing factor for exponential moving average
    /// 0.5 = 50% new data, 50% old average (balanced responsiveness)
    private let smoothingFactor: Double = 0.5
    
    // MARK: - RMS History Buffer
    /// Buffer storing recent RMS values for averaging (reduces false positives)
    private var rmsHistory: [Float] = []
    
    /// Maximum size of RMS history buffer
    private let rmsHistorySize: Int = 8
    
    /// Flag to control haptic triggering
    private var shouldTriggerHaptic: Bool = false
    
    
    // MARK: - Start Monitoring
    /// Initiates audio monitoring and WPM calculation
    /// Requests microphone permission if not already granted
    func startMonitoring() {
        // Prevent starting if already monitoring
        guard !isMonitoring else {
            return
        }
        
        // Request microphone permission asynchronously
        Task {
            let authorized = await requestMicrophonePermission()
            
            if authorized {
                // Update UI on main thread
                await MainActor.run {
                    self.statusMessage = "Starting..."
                    self.isMonitoring = true
                    self.resetMetrics()
                    self.setupAudioEngine()
                    self.startCalculationTimer()
                }
            } else {
                // Handle denied permission
                await MainActor.run {
                    self.statusMessage = "Microphone access denied. Check the settings."
                    self.isMonitoring = false
                }
            }
        }
    }
    
    // MARK: - Stop Monitoring
    /// Stops audio monitoring and cleans up resources
    func stopMonitoring() {
        // Prevent stopping if not monitoring
        guard isMonitoring else {
            return
        }
        
        isMonitoring = false
        statusMessage = "Ready"
        
        // Invalidate and clear calculation timer
        calculationTimer?.invalidate()
        calculationTimer = nil
        
        // Stop audio engine and remove audio tap
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            print("Monitoring and Audio Engine stopped.")
        }
        
        resetMetrics()
    }
    
    // MARK: - Microphone Permission
    /// Requests microphone recording permission from the user
    /// - Returns: Boolean indicating whether permission was granted
    private func requestMicrophonePermission() async -> Bool {
        let status = await AVAudioApplication.requestRecordPermission()
        return status
    }
    
    // MARK: - Audio Engine Setup
    /// Configures and starts the AVAudioEngine for microphone input processing
    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        self.audioEngine = engine
        
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        // Install tap on audio input for real-time processing
        // Buffer size: 1024 samples
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) {
            [weak self] (buffer, time) in
            self?.processAudioBuffer(buffer: buffer)
        }
        
        do {
            try engine.start()
            print("Starting AVAudioEngine...")
            statusMessage = "Monitoring..."
        } catch {
            print("Error starting AVAudioEngine: \(error.localizedDescription)")
            stopMonitoring()
            statusMessage = "Audio error"
        }
    }
    
    // MARK: - Voice Activity Detection
    /// Processes audio buffer to detect voice activity
    /// Uses RMS (energy) and peak amplitude to distinguish speech from noise
    /// - Parameter buffer: Audio buffer containing PCM samples
    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
        // Extract audio data from buffer
        guard let data = buffer.floatChannelData else {
            return
        }
        
        let frameLength = buffer.frameLength
        let sampleRate = buffer.format.sampleRate
        
        // Calculate RMS (Root Mean Square) for audio energy
        var sumOfSquares: Float = 0.0
        var peakAmplitude: Float = 0.0
        
        for i in 0..<Int(frameLength) {
            let sample = data.pointee[i]
            sumOfSquares += sample * sample
            peakAmplitude = max(peakAmplitude, abs(sample))
        }
        
        // RMS = measure of average signal energy
        let rms = sqrt(sumOfSquares / Float(frameLength))
        
        // Duration of this audio buffer
        let bufferDuration = Double(frameLength) / sampleRate
        
        // Add RMS to history buffer for smoothing
        rmsHistory.append(rms)
        if rmsHistory.count > rmsHistorySize {
            rmsHistory.removeFirst()
        }
        
        // Calculate average RMS from history (reduces noise sensitivity)
        let avgRMS = rmsHistory.reduce(0, +) / Float(rmsHistory.count)
        
        // Voice detection: requires BOTH sufficient average energy AND peak amplitude
        // This combination helps distinguish human voice from constant background noise
        let isLikelyVoice = avgRMS > rmsThreshold && peakAmplitude > peakThreshold
        
        if isLikelyVoice {
            // Voice detected - accumulate speaking time
            totalSpeakingTime += bufferDuration
            currentSilenceFrames = 0
            print("Voice detected - RMS: \(avgRMS), Peak: \(peakAmplitude)")
        } else {
            // Silence or noise - increment silence counter
            currentSilenceFrames += 1
        }
        
        // Always accumulate total monitoring time
        totalMonitoringTime += bufferDuration
    }
    
    // MARK: - Calculation Timer
    /// Starts a repeating timer that triggers WPM calculation at regular intervals
    private func startCalculationTimer() {
        calculationTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) {
            [weak self] _ in
            self?.calculateAndCheckRate()
        }
    }
    
    // MARK: - WPM Calculation
    /// Calculates current WPM based on speaking time density
    /// Updates UI and triggers haptic feedback if thresholds are exceeded
    private func calculateAndCheckRate() {
        // Wait until we have a complete observation interval
        guard totalMonitoringTime >= updateInterval else {
            DispatchQueue.main.async {
                self.statusMessage = "Monitoring: \(Int(self.totalMonitoringTime))s"
            }
            return
        }

        // Calculate speaking density (ratio of speaking time to total time)
        let instantaneousDensity = totalSpeakingTime / totalMonitoringTime
        
        // WPM estimation parameters
        let minWPM: Int = 60   // Minimum possible WPM (slow speech)
        let maxWPM: Int = 300  // Maximum possible WPM (very fast speech)
        
        // Linear interpolation based on speaking density
        let instantaneousRate = Int(Float(minWPM) + (Float(maxWPM - minWPM) * Float(instantaneousDensity)))
        
        // Apply exponential moving average (smoothing) if we have previous data
        let newWPM: Double
        if currentWPM > 0 {
            // Blend old and new values for smooth transitions
            newWPM = Double(currentWPM) * (1.0 - smoothingFactor) + Double(instantaneousRate) * smoothingFactor
        } else {
            // First calculation - use raw value
            newWPM = Double(instantaneousRate)
        }
        
        print("📊 Density: \(String(format: "%.2f", instantaneousDensity)), Instantaneous WPM: \(instantaneousRate), Smoothed WPM: \(Int(newWPM))")
        
        let finalWPM = Int(round(newWPM))
        
        // Determine if haptic feedback is needed before switching to main thread
        let needsHaptic = finalWPM > wpmThreshold
        
        // Update UI and trigger haptic on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update current WPM
            self.currentWPM = finalWPM
            print("✅ WPM updated to: \(finalWPM)")
            
            // Check thresholds and update status
            if needsHaptic {
                print("⚠️ THRESHOLD EXCEEDED: \(finalWPM) > \(self.wpmThreshold)")
                self.statusMessage = "Slow down! (\(finalWPM) WPM)"
                self.triggerHapticFeedback()
            } else if finalWPM < self.wpmThresholdMin && finalWPM > 0 {
                self.statusMessage = "Speed up! (\(finalWPM) WPM)"
            } else if self.isMonitoring {
                self.statusMessage = "OK (\(finalWPM) WPM)"
            }
        }
        
        // Reset metrics for next interval (after sending to main thread)
        totalSpeakingTime = 0.0
        totalMonitoringTime = 0.0
    }
    
    // MARK: - Reset Metrics
    /// Resets all monitoring metrics and buffers to initial state
    private func resetMetrics() {
        totalSpeakingTime = 0.0
        totalMonitoringTime = 0.0
        currentWPM = 0
        lastHapticTime = nil
        rmsHistory.removeAll()
        currentSilenceFrames = 0
        shouldTriggerHaptic = false
    }
    
    // MARK: - Haptic Feedback
        /// Triggers haptic feedback on Apple Watch
        /// CRITICAL: Must be executed on main thread for haptics to work
        /// Implements cooldown to prevent excessive vibrations
        /// Provides a gentle, prolonged 3-second vibration pattern to alert user
        private func triggerHapticFeedback() {
            // Verify execution on main thread (crashes in debug if violated)
            assert(Thread.isMainThread, "⛔️ triggerHapticFeedback must execute on main thread")
            
            let now = Date()
            
            // Check cooldown period
            if let lastTime = lastHapticTime {
                let timeSince = now.timeIntervalSince(lastTime)
                if timeSince < hapticCooldown {
                    print("⏱️ Haptic in cooldown - \(String(format: "%.1f", timeSince))s since last (requires \(hapticCooldown)s)")
                    return
                }
            }
            
            print("🔴🔴🔴 TRIGGERING PROLONGED VIBRATION PATTERN - WPM: \(currentWPM) 🔴🔴🔴")
            
            // Create a gentle, prolonged vibration pattern over ~3 seconds
            // Using multiple soft haptics with spacing for a smooth, noticeable alert
            
            // Initial gentle tap (t=0s)
            WKInterfaceDevice.current().play(.directionDown)
            
            // Soft pulse series to create prolonged sensation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                WKInterfaceDevice.current().play(.directionDown)
                print("🔴 Pulse 1")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                WKInterfaceDevice.current().play(.directionDown)
                print("🔴 Pulse 2")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                WKInterfaceDevice.current().play(.directionDown)
                print("🔴 Pulse 3")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                WKInterfaceDevice.current().play(.directionDown)
                print("🔴 Pulse 4")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                WKInterfaceDevice.current().play(.directionDown)
                print("🔴 Pulse 5")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                WKInterfaceDevice.current().play(.directionDown)
                print("🔴 Pulse 6")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
                WKInterfaceDevice.current().play(.directionDown)
                print("🔴 Pulse 7")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                WKInterfaceDevice.current().play(.directionDown)
                print("🔴 Pulse 8")
            }
            
            // Final gentle tap to conclude pattern (t=2.7s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
                WKInterfaceDevice.current().play(.directionDown)
                print("🔴 Final pulse - vibration pattern complete")
            }
            
            // Update last haptic timestamp
            lastHapticTime = now
            print("✅ Last vibration timestamp updated to: \(now)")
        }
    }
