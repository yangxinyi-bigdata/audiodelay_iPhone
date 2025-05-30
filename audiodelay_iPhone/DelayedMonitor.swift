import AVFoundation
import UIKit

class DelayedMonitor {
    private let engine = AVAudioEngine()
    private let delay = AVAudioUnitDelay()
    private var selectedInput: AVAudioSessionPortDescription?
    private var selectedOutput: AVAudioSessionPortDescription?
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    // 添加音频监控相关属性
    private var audioLevelUpdateTimer: Timer?
    private var currentAudioLevel: Float = 0.0
    var onAudioLevelUpdate: ((Float) -> Void)?
    
    // 添加录音相关属性
    private var audioFile: AVAudioFile?
    private var isRecording = false
    private var recordingURL: URL?
    private var inputFormat: AVAudioFormat?
    
    // 添加录音状态回调
    var onRecordingStatusChanged: ((Bool) -> Void)?
    
    deinit {
        endBackgroundTask()
        removeObservers()
    }
    
    private func removeObservers() {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
        
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }
    
    private func beginBackgroundTask() {
        // 如果已经有一个后台任务，先结束它
        endBackgroundTask()
        
        // 开始一个新的后台任务
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    // 辅助函数：获取端口类型的友好名称
    private static func getPortTypeName(_ portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInMic:
            return "内置麦克风"
        case .headsetMic:
            return "耳机麦克风"
        case .bluetoothHFP:
            return "蓝牙耳机"
        case .usbAudio:
            return "USB设备"
        case .bluetoothA2DP:
            return "蓝牙A2DP"
        case .builtInSpeaker:
            return "内置扬声器"
        case .headphones:
            return "有线耳机"
        case .bluetoothLE:
            return "蓝牙LE设备"
        case .airPlay:
            return "AirPlay设备"
        default:
            return portType.rawValue
        }
    }
    
    static func getAvailableInputs() -> [(id: String, name: String)] {
        var inputs: [(id: String, name: String)] = []
        let session = AVAudioSession.sharedInstance()
        
        do {
            // 配置音频会话以支持更多类型的输入设备
            try session.setCategory(.playAndRecord, options: [
                .defaultToSpeaker,
                .allowBluetooth,
                .allowBluetoothA2DP,
                .allowAirPlay,
                .mixWithOthers
            ])
            
            try session.setActive(true)
            
            // 获取所有可用输入
            guard let availableInputs = session.availableInputs else {
                print("没有找到可用的输入设备")
                return []
            }
            
            print("\n=== 音频输入设备列表 ===")
            for input in availableInputs {
                let portTypeName = getPortTypeName(input.portType)
                print("发现输入设备: \(input.portName) (\(portTypeName))")
                inputs.append((id: input.uid, name: "\(input.portName) (\(portTypeName))"))
            }
            
        } catch {
            print("获取输入设备时出错: \(error.localizedDescription)")
        }
        
        return inputs
    }

    static func getAvailableOutputs() -> [(id: String, name: String)] {
        var outputs: [(id: String, name: String)] = []
        let session = AVAudioSession.sharedInstance()
        
        do {
            // 获取当前可用的输出设备
            let currentRoute = session.currentRoute
            print("\n=== 音频输出设备列表 ===")
            
            // 添加当前可用的输出端口
            for output in currentRoute.outputs {
                let portTypeName = getPortTypeName(output.portType)
                print("发现输出设备: \(output.portName) (\(portTypeName))")
                outputs.append((id: output.uid, name: "\(output.portName) (\(portTypeName))"))
            }
            
        } catch {
            print("获取输出设备时出错: \(error.localizedDescription)")
        }
        
        return outputs
    }

    init(delaySeconds: TimeInterval, inputUID: String? = nil, outputUID: String? = nil) {
        let session = AVAudioSession.sharedInstance()
        
        // 设置输入设备
        if let uid = inputUID {
            selectedInput = session.availableInputs?.first(where: { $0.uid == uid })
            print("选择输入设备: \(selectedInput?.portName ?? "未找到") (UID: \(uid))")
        }
        
        // 设置输出设备
        if let uid = outputUID {
            selectedOutput = session.currentRoute.outputs.first(where: { $0.uid == uid })
            print("选择输出设备: \(selectedOutput?.portName ?? "未找到") (UID: \(uid))")
        }
        
        configureAudioSession()
        buildEngineGraph(delaySeconds: delaySeconds)
        startEngine()
    }

    func updateDelay(seconds: TimeInterval) {
        delay.delayTime = seconds
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // 根据是否选择了扬声器来设置选项
            var options: AVAudioSession.CategoryOptions = [
                .allowBluetooth,
                .allowBluetoothA2DP,
                .allowAirPlay,
                .mixWithOthers
            ]
            
            // 如果选择了内置扬声器或者没有选择输出设备，则默认使用扬声器
            if selectedOutput?.portType == .builtInSpeaker || selectedOutput == nil {
                options.insert(.defaultToSpeaker)
            }
            
            // 设置音频会话类别和选项
            try session.setCategory(.playAndRecord, mode: .default, options: options)
            try session.setPreferredIOBufferDuration(0.01)
            
            // 设置输入设备
            if let input = selectedInput {
                try session.setPreferredInput(input)
                print("""
                    成功设置输入设备:
                    名称: \(input.portName)
                    类型: \(DelayedMonitor.getPortTypeName(input.portType))
                    UID: \(input.uid)
                    """)
            }
            
            // 如果选择了特定的输出设备，尝试覆盖默认路由
            if let output = selectedOutput {
                print("""
                    尝试设置输出设备:
                    名称: \(output.portName)
                    类型: \(DelayedMonitor.getPortTypeName(output.portType))
                    UID: \(output.uid)
                    """)
            }
            
            try session.setActive(true)
            
            // 添加路由变化观察者
            routeChangeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleRouteChange(notification)
            }
            
            // 添加中断观察者
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleInterruption(notification)
            }
            
            // 打印最终的音频路由
            print("\n当前音频路由:")
            if let currentInput = session.currentRoute.inputs.first {
                print("输入: \(currentInput.portName) (\(DelayedMonitor.getPortTypeName(currentInput.portType)))")
            }
            if let currentOutput = session.currentRoute.outputs.first {
                print("输出: \(currentOutput.portName) (\(DelayedMonitor.getPortTypeName(currentOutput.portType)))")
            }
            
        } catch {
            print("配置音频会话失败: \(error.localizedDescription)")
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        print("\n音频路由发生变化:")
        print("原因: \(reason)")
        
        // 检查引擎状态
        let wasRunning = engine.isRunning
        
        // 根据不同的路由变化原因采取不同的措施
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .routeConfigurationChange:
            // 设备切换或设备配置变化
            print("设备变化，尝试恢复音频路由")
            
            // 先暂停引擎
            if engine.isRunning {
                engine.pause()
            }
            
            // 重新配置音频会话
            configureAudioSession()
            
            // 尝试重启引擎
            if wasRunning {
                restartEngine()
            }
            
        default:
            // 其他变化类型，也尝试保持引擎运行
            print("其他路由变化: \(reason.rawValue)，保持引擎运行")
            
            // 检查引擎是否还在运行
            if wasRunning && !engine.isRunning {
                restartEngine()
            }
        }
    }
    
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        print("\n音频会话被中断:")
        
        if type == .began {
            print("中断开始")
            // 中断开始，暂停引擎
            if engine.isRunning {
                engine.pause()
            }
        } else if type == .ended {
            // 中断结束，检查是否应该恢复
            print("中断结束")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    print("尝试恢复音频引擎")
                    // 重新配置音频会话
                    configureAudioSession()
                    // 重启引擎
                    try? engine.start()
                }
            }
        }
    }
    
    private func restartEngine() {
        // 停止引擎
        engine.stop()
        
        // 等待一小段时间确保引擎完全停止
        Thread.sleep(forTimeInterval: 0.1)
        
        // 重建引擎图
        buildEngineGraph(delaySeconds: delay.delayTime)
        
        // 尝试重启
        do {
            try engine.start()
            print("引擎成功重启")
        } catch {
            print("引擎重启失败: \(error)")
            
            // 如果重启失败，等待一小段时间后重试
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                
                do {
                    try self.engine.start()
                    print("引擎延迟重启成功")
                } catch {
                    print("引擎延迟重启失败: \(error)")
                }
            }
        }
    }

    private func buildEngineGraph(delaySeconds: TimeInterval) {
        // 配置延迟效果
        delay.delayTime = delaySeconds
        delay.feedback = 0
        delay.wetDryMix = 100
        
        // 获取输入节点
        let inputNode = engine.inputNode
        inputFormat = inputNode.outputFormat(forBus: 0)
        
        // 附加延迟节点到引擎
        engine.attach(delay)
        
        // 连接节点
        engine.connect(inputNode, to: delay, format: inputFormat)
        engine.connect(delay, to: engine.mainMixerNode, format: inputFormat)
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

    private func setupRecordingTap() {
        guard let inputFormat = inputFormat else { return }
        
        // 创建录音文件
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let appFolder = documentsPath.appendingPathComponent("Recordings", isDirectory: true)
        
        // 确保文件夹存在
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true, attributes: nil)
        
        // 创建唯一的文件名
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "recording_\(dateFormatter.string(from: Date())).wav"
        recordingURL = appFolder.appendingPathComponent(fileName)
        
        // 设置音频格式
        var audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        do {
            audioFile = try AVAudioFile(forWriting: recordingURL!, settings: audioSettings)
            print("录音文件将保存到: \(recordingURL!.path)")
        } catch {
            print("创建录音文件失败: \(error.localizedDescription)")
            return
        }
        
        // 安装录音 tap
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // 计算音频电平
            let channelData = buffer.floatChannelData?[0]
            let frameLength = UInt32(buffer.frameLength)
            var sum: Float = 0
            
            for i in 0..<Int(frameLength) {
                let sample = channelData?[i] ?? 0
                sum += sample * sample
            }
            
            let rms = sqrt(sum / Float(frameLength))
            let db = 20 * log10(rms)
            let normalizedValue = (db + 50) / 50 // 将 -50dB 到 0dB 映射到 0 到 1
            
            DispatchQueue.main.async {
                self.currentAudioLevel = max(0, min(1, normalizedValue))
                self.onAudioLevelUpdate?(self.currentAudioLevel)
            }
            
            // 如果正在录音，写入文件
            if self.isRecording {
                do {
                    // 创建新的缓冲区，使用正确的格式
                    let convertedBuffer = AVAudioPCMBuffer(pcmFormat: self.audioFile!.processingFormat,
                                                         frameCapacity: buffer.frameCapacity)!
                    convertedBuffer.frameLength = buffer.frameLength
                    
                    // 直接复制音频数据
                    if let inputData = buffer.floatChannelData?[0],
                       let outputData = convertedBuffer.floatChannelData?[0] {
                        let frameCount = Int(buffer.frameLength)
                        for i in 0..<frameCount {
                            outputData[i] = inputData[i]
                        }
                    }
                    
                    // 写入转换后的缓冲区
                    try self.audioFile?.write(from: convertedBuffer)
                } catch {
                    print("写入录音文件失败: \(error.localizedDescription)")
                }
            }
        }
    }

    private func removeRecordingTap() {
        engine.inputNode.removeTap(onBus: 0)
        // 确保文件被正确关闭
        audioFile = nil
    }

    func startRecording() {
        if !isRecording {
            setupRecordingTap()
            isRecording = true
            onRecordingStatusChanged?(true)
        }
    }
    
    func stopRecording() {
        if isRecording {
            isRecording = false
            onRecordingStatusChanged?(false)
            removeRecordingTap()
        }
    }
    
    func saveRecording() -> URL? {
        stopRecording()
        // 确保文件被正确关闭
        audioFile = nil
        return recordingURL
    }
    
    func discardRecording() {
        stopRecording()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }

    func stop() {
        endBackgroundTask()
        removeObservers()
        removeRecordingTap()
        engine.stop()
        engine.reset()
        
        // 确保文件被正确关闭
        audioFile = nil
        
        // 关闭音频会话
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("关闭音频会话失败: \(error)")
        }
    }
}

