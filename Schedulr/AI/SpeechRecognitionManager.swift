//
//  SpeechRecognitionManager.swift
//  Schedulr
//
//  Created by Daniel Block on 28/11/2025.
//

import Foundation
import Speech
import AVFoundation
import Combine

/// Manages speech recognition for voice input to the AI assistant
@MainActor
final class SpeechRecognitionManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var transcribedText: String = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var authorizationStatus: SpeechAuthorizationStatus = .notDetermined
    
    enum SpeechAuthorizationStatus {
        case notDetermined
        case authorized
        case denied
        case restricted
        case microphoneDenied
    }
    
    // MARK: - Private Properties
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // MARK: - Initialization
    
    init() {
        // Initialize with user's locale for better recognition
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        
        // Check initial authorization status
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    // MARK: - Authorization
    
    /// Check current authorization status for both speech recognition and microphone
    func checkAuthorizationStatus() async {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        
        switch speechStatus {
        case .authorized:
            // Also check microphone permission
            let micStatus = await checkMicrophonePermission()
            if micStatus {
                authorizationStatus = .authorized
            } else {
                authorizationStatus = .microphoneDenied
            }
        case .denied:
            authorizationStatus = .denied
        case .restricted:
            authorizationStatus = .restricted
        case .notDetermined:
            authorizationStatus = .notDetermined
        @unknown default:
            authorizationStatus = .notDetermined
        }
    }
    
    private func checkMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    /// Request authorization for speech recognition and microphone
    /// Returns true if both are authorized
    func requestAuthorization() async -> Bool {
        // First request speech recognition permission
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        
        guard speechAuthorized else {
            await MainActor.run {
                authorizationStatus = .denied
                errorMessage = "Speech recognition permission is required for voice input."
            }
            return false
        }
        
        // Then request microphone permission
        let micAuthorized = await checkMicrophonePermission()
        
        guard micAuthorized else {
            await MainActor.run {
                authorizationStatus = .microphoneDenied
                errorMessage = "Microphone permission is required for voice input."
            }
            return false
        }
        
        await MainActor.run {
            authorizationStatus = .authorized
            errorMessage = nil
        }
        
        return true
    }
    
    // MARK: - Recording Control
    
    /// Start recording and transcribing speech
    func startRecording() async {
        // Clear previous state
        transcribedText = ""
        errorMessage = nil
        
        // Check authorization
        if authorizationStatus != .authorized {
            let authorized = await requestAuthorization()
            guard authorized else { return }
        }
        
        // Check if speech recognizer is available
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available on this device."
            return
        }
        
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to configure audio session: \(error.localizedDescription)"
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Failed to create speech recognition request."
            return
        }
        
        // Configure for real-time results
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        
        // Get input node
        let inputNode = audioEngine.inputNode
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let result = result {
                    self.transcribedText = result.bestTranscription.formattedString
                }
                
                if let error = error {
                    // Don't show error if it's just because we stopped recording
                    if (error as NSError).code != 1 && (error as NSError).code != 216 {
                        self.errorMessage = "Recognition error: \(error.localizedDescription)"
                    }
                }
                
                if error != nil || (result?.isFinal ?? false) {
                    self.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    self.isRecording = false
                }
            }
        }
        
        // Configure audio tap
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            isRecording = false
        }
    }
    
    /// Stop recording and finalize transcription
    func stopRecording() {
        guard isRecording else { return }
        
        audioEngine.stop()
        recognitionRequest?.endAudio()
        
        // Clean up will happen in the recognition task callback
        isRecording = false
    }
    
    /// Toggle recording state
    func toggleRecording() async {
        if isRecording {
            stopRecording()
        } else {
            await startRecording()
        }
    }
    
    /// Clear transcribed text and error
    func clearTranscription() {
        transcribedText = ""
        errorMessage = nil
    }
}

