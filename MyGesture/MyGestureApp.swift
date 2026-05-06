import SwiftUI

@main
struct MyGestureApp: App {
    // 🌟 把「手勢管理者」放在這裡，確保它永遠在背景存活，不會被系統殺掉
    @StateObject var gestureManager = GestureManager()

    var body: some Scene {
        MenuBarExtra("我的手勢", systemImage: "hand.point.up.left.fill") {
            
            // 🌟 修正警告：改用 Apple 原生的 SettingsLink
            SettingsLink {
                Label("偏好設定...", systemImage: "gearshape")
            }
            
            Divider() // 畫一條分隔線
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("結束 MyGesture", systemImage: "xmark.square")
            }
        }

        // 🌟 這裡定義了「偏好設定...」點開後要出現的視窗
        Settings {
            ContentView(gestureManager: gestureManager)
        }
    }
}
