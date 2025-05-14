import SwiftUI
import AVFoundation

struct AudioLevelMeter: View {
    let level: Float
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray6))
                
                // 音量条
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue)
                    .frame(width: max(2, geometry.size.width * CGFloat(level)))
            }
        }
    }
}

struct ContentView: View {
    @State private var delaySeconds: Double = 3.0
    @State private var monitor: DelayedMonitor? = nil
    @State private var availableInputs: [(id: String, name: String)] = []
    @State private var availableOutputs: [(id: String, name: String)] = []
    @State private var selectedInputID: String? = nil
    @State private var selectedOutputID: String? = nil
    @State private var audioLevel: Float = 0.0
    
    var body: some View {
        VStack(spacing: 30) {
            Text("麦克风声音延迟监听")
                .font(.title2)
                .padding()
            
            // 添加音频条
            AudioLevelMeter(level: audioLevel)
                .frame(width: 200, height: 20)
                .padding()
            
            VStack(alignment: .leading, spacing: 15) {
                // 输入设备选择
                if !availableInputs.isEmpty {
                    Text("选择输入设备:")
                        .font(.headline)
                    Picker("输入设备", selection: $selectedInputID) {
                        Text("默认麦克风").tag(nil as String?)
                        ForEach(availableInputs, id: \.id) { input in
                            Text(input.name).tag(input.id as String?)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // 输出设备选择
                if !availableOutputs.isEmpty {
                    Text("选择输出设备:")
                        .font(.headline)
                    Picker("输出设备", selection: $selectedOutputID) {
                        Text("默认扬声器").tag(nil as String?)
                        ForEach(availableOutputs, id: \.id) { output in
                            Text(output.name).tag(output.id as String?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.horizontal)

            Slider(value: $delaySeconds, in: 0...5, step: 0.1) {
                Text("延迟时间")
            }
            .padding()

            Text(String(format: "当前延迟: %.1f 秒", delaySeconds))

            HStack(spacing: 20) {
                Button("开始监听") {
                    monitor = DelayedMonitor(
                        delaySeconds: delaySeconds,
                        inputUID: selectedInputID,
                        outputUID: selectedOutputID
                    )
                    // 设置音频电平更新回调
                    monitor?.onAudioLevelUpdate = { level in
                        audioLevel = level
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("更新延迟") {
                    monitor?.updateDelay(seconds: delaySeconds)
                }

                Button("停止") {
                    monitor?.stop()
                    monitor = nil
                    audioLevel = 0
                }
                .foregroundColor(.red)
            }
            
            Button("刷新设备列表") {
                refreshDevices()
            }
            .padding(.top)
        }
        .padding()
        .onAppear {
            refreshDevices()
        }
    }
    
    private func refreshDevices() {
        availableInputs = DelayedMonitor.getAvailableInputs()
        availableOutputs = DelayedMonitor.getAvailableOutputs()
    }
}
