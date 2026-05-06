import SwiftUI

@main
struct MyGestureApp: App {
    var body: some Scene {
        // 這裡就是把它變成選單列圖示的魔法
        MenuBarExtra("我的手勢", systemImage: "hand.point.up.left.fill") {
            ContentView() // 把我們原本寫好的畫面放進來
            
            Divider() // 畫一條分隔線
            
            // 加一個可以真正關閉 App 的按鈕
            Button("結束程式") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.window) // 讓它點選後像個小視窗掉下來
    }
}
