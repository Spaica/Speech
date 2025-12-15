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

// MARK: CLASS SPEAKINGRATEMONITOR
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
    private var rmsThreshold: Float = 0.01 //REMEMBER TO INCREASE THIS NUMBER IF IT DETECTS TO MUCH NOISE
    

    private var audioEngine: AVAudioEngine?
    private var lastHapticTime: Date?
    private let hapticCooldown: TimeInterval = 3.0
    
    private var totalSpeakingTime: TimeInterval = 0.0
    private var totalMonitoringTime: TimeInterval = 0.0
    private let updateInterval: TimeInterval = 1.0
    private var calculationTimer: Timer?
    
    //Damping factor for the sliding average
    //0.2: 20% is from new data, 80% from the old average.
    private let smoothingFactor: Double = 0.6 //the closer the value to 1, the faster the update
    
    
    // MARK: Start monitoring
    func startMonitoring() {
        //check
        guard !isMonitoring else {
            return
        }
        
        //microphone authorization
        Task { //not blocking, separate thread
            let authorized = await requestMicrophonePermission() //bool: is the permission given?
            
            if authorized {
                //setup on the main actor for ui updates: the main actor makes sure that the code is executed on the main thread (all the ui updates have to be executed on the main thread)
                await MainActor.run {
                    self.statusMessage = "Starting..."
                    self.isMonitoring = true
                    self.resetMetrics()
                    self.setupAudioEngine()
                    self.startCalculationTimer()
                }
            } else {
                await MainActor.run {
                    self.statusMessage = "Microphone access denied. Check the settings."
                    self.isMonitoring = false
                }
            }
        }
    }
    
    // MARK: End monitoring
    func stopMonitoring() {
        //check
        guard isMonitoring else {
            return
        }
        
        isMonitoring = false
        statusMessage = "Ready"
        calculationTimer?.invalidate()
        calculationTimer = nil
        
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            print("Monitoring and Audio Engine arrested.")
        }
        resetMetrics()
    }
    
    // MARK: Permissions request
    private func requestMicrophonePermission() async -> Bool {
        let status = await AVAudioApplication.requestRecordPermission() //system call
        return status
    }
    
    // MARK: Set up Audio Engine
    private func setupAudioEngine() {
        let engine = AVAudioEngine() //handles the sound elaboration
        self.audioEngine = engine //set the object engine in my speakingratemonitor engine
        
        let inputNode = engine.inputNode //take the input node
        let format = inputNode.outputFormat(forBus: 0) //output format on the standard bus
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) {
            [weak self] (buffer, time) in //weak self is for problems of deallocation with objects with multiple references
            self?.processAudioBuffer(buffer: buffer)
        }
        
        do {
            try engine.start()
            print("Starting AVAudioEngine...")
            statusMessage = "Monitoring..."
        } catch {
            print("Error in starting AVAudioEngine: \(error.localizedDescription)")
            stopMonitoring()
            statusMessage = "Audio error"
        }
    }
    
    // MARK: Voice Activity Detection
    private func processAudioBuffer(buffer: AVAudioPCMBuffer) { //buffer for not compressed audio data
        //check
        guard let data = buffer.floatChannelData else {
            return
        }
        let frameLength = buffer.frameLength //1 frame = 1 sample because we are using only one channel, quindi 1024 frame totali
        let sampleRate = buffer.format.sampleRate //framelenght/time range, how many frames in a time range
        
        //RMS to measure the energy of the signal
        var sumOfSquares: Float = 0.0
        for i in 0..<Int(frameLength) { //from 0 to frames in a time range
            let sample = data.pointee[i] //collect all the frames in an array, .pointee is for accessing to the real pointer value and not just the pointer
            sumOfSquares += sample * sample
        }
        let rms = sqrt(sumOfSquares / Float(frameLength))
        let bufferDuration = Double(frameLength) / sampleRate
        
        //if the rms is above the minimum threshold of the noise, we register vocal activity
        if rms > rmsThreshold {
            totalSpeakingTime += bufferDuration
        }
        totalMonitoringTime += bufferDuration
    }
    
    // MARK: Timer
    private func startCalculationTimer() {
        //timer is for making sure that the WPN calculation and the UI updates happen at regular intervals
        calculationTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { //time interval of 1.00, in infinite loop
            [weak self] _ in
            self?.calculateAndCheckRate() //executed every time interval
        }
    }
    
    // MARK: WPN calculation
    private func calculateAndCheckRate() {
            //check for a complete observing interval
            guard totalMonitoringTime >= updateInterval else {
                //updates UI without calculating WPN
                DispatchQueue.main.async {
                    self.statusMessage = "Monitoring: \(Int(self.totalMonitoringTime))s"
                }
                return
            }

            let instantaneousDensity = totalSpeakingTime / totalMonitoringTime
            
            //WPN only for this interval
            let minWPM: Int = 60
            let maxWPM: Int = 300
            
            let instantaneousRate = Int(Float(minWPM) + (Float(maxWPM - minWPM) * Float(instantaneousDensity)))
        
            let newWPM = Double(currentWPM) * (1.0 - smoothingFactor) + Double(instantaneousRate) * smoothingFactor
            
            //reset only for that window
            totalSpeakingTime = 0.0
            totalMonitoringTime = 0.0
            
        
        //Updates the UI
        DispatchQueue.main.async {
            self.currentWPM = Int(round(newWPM))
            self.checkThreshold()
        }
    }
    
    // MARK: Reset metrics
    private func resetMetrics() {
        totalSpeakingTime = 0.0
        totalMonitoringTime = 0.0
        currentWPM = 0
        lastHapticTime = nil
    }
    
    // MARK: Check thresholds
    private func checkThreshold() {
        if currentWPM > wpmThreshold {
            triggerHapticFeedback()
            statusMessage = "Slow down!"
        } else if isMonitoring {
            statusMessage = "OK"
        }
    }
    
    // MARK: Haptics
    private func triggerHapticFeedback() {
        let now = Date()
        //cooldown
        if let lastTime = lastHapticTime, now.timeIntervalSince(lastTime) < hapticCooldown {
            return
        }
        
        //vibration
        WKInterfaceDevice.current().play(.notification)
        print("VIBRAZION: Threshold \(wpmThreshold) WPM exceeded (\(currentWPM) WPM).")
        lastHapticTime = now
    }
}
