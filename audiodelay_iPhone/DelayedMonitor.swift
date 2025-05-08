import AVFoundation

class DelayedMonitor {
    private let engine = AVAudioEngine()
    private let delay = AVAudioUnitDelay()
    private var selectedInput: AVAudioSessionPortDescription?
    private var selectedOutput: AVAudioSessionPortDescription?
    
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
            
            try session.setCategory(.playAndRecord, options: options)
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
                // 注意：iOS可能不允许直接设置某些输出设备，这取决于系统策略
                print("""
                    尝试设置输出设备:
                    名称: \(output.portName)
                    类型: \(DelayedMonitor.getPortTypeName(output.portType))
                    UID: \(output.uid)
                    """)
            }
            
            try session.setActive(true)
            
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

