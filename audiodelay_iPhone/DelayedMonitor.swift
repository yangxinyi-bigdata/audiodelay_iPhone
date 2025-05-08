import AVFoundation

class DelayedMonitor {
    private let engine = AVAudioEngine()
    private let delay = AVAudioUnitDelay()

    init(delaySeconds: TimeInterval) {
        configureAudioSession()
        buildEngineGraph(delaySeconds: delaySeconds)
        startEngine()
    }

    func updateDelay(seconds: TimeInterval) {
        delay.delayTime = seconds
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setPreferredIOBufferDuration(0.01)
        try? session.setActive(true)
    }

    private func buildEngineGraph(delaySeconds: TimeInterval) {
        delay.delayTime = delaySeconds
        delay.feedback = 0
        delay.wetDryMix = 100

        engine.attach(delay)
        let format = engine.inputNode.inputFormat(forBus: 0)
        engine.connect(engine.inputNode, to: delay, format: format)
        engine.connect(delay, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
    }

    private func startEngine() {
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("音频引擎启动失败: \(error)")
        }
    }

    func stop() {
        engine.stop()
        engine.reset()
    }
}
