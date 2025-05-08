import SwiftUI

struct ContentView: View {
    @State private var delaySeconds: Double = 3.0
    @State private var monitor: DelayedMonitor? = nil

    var body: some View {
        VStack(spacing: 30) {
            Text("麦克风声音延迟监听")
                .font(.title2)
                .padding()

            Slider(value: $delaySeconds, in: 0...5, step: 0.1) {
                Text("延迟时间")
            }
            .padding()

            Text(String(format: "当前延迟: %.1f 秒", delaySeconds))

            HStack(spacing: 20) {
                Button("开始监听") {
                    monitor = DelayedMonitor(delaySeconds: delaySeconds)
                }
                .buttonStyle(.borderedProminent)

                Button("更新延迟") {
                    monitor?.updateDelay(seconds: delaySeconds)
                }

                Button("停止") {
                    monitor?.stop()
                    monitor = nil
                }
                .foregroundColor(.red)
            }
        }
        .padding()
    }
}
