import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // 🌟 準備一個變數來存放我們的「偏好設定視窗」
    var settingsWindow: NSWindow?
    
    // 🌟 直接把手勢管理者交給 AppDelegate 永遠保管，保證它絕對不會死掉！
    let gestureManager = GestureManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App 第一次啟動時，直接打開視窗
        openSettingsWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 任何時候雙擊 App Icon，打開視窗
        openSettingsWindow()
        return true
    }
    
    // 🌟 這是我們自己手作的「無敵開視窗魔法」
    @objc func openSettingsWindow() {
        // 1. 強制把這支幕後 App 喚醒，拉到系統最上層
        NSApp.activate(ignoringOtherApps: true)
        
        // 2. 檢查視窗是不是已經存在了？
        if let window = settingsWindow {
            // 如果存在，直接把它叫到最前面！
            window.makeKeyAndOrderFront(nil)
        } else {
            // 如果不存在，我們自己用蘋果底層 API 打造一個完美視窗
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 320),
                styleMask:[.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: "app_name")
            window.center() // 讓視窗出現在螢幕正中央
            window.isReleasedWhenClosed = false // 🌟 關鍵：關閉時不要銷毀記憶體，這樣才能秒開
            
            // 把你寫好的完美 SwiftUI 畫面，塞進這個底層視窗裡！
            window.contentView = NSHostingView(rootView: ContentView(gestureManager: gestureManager))
            
            // 存起來，然後推到最前面！
            self.settingsWindow = window
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct MyGestureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("app_name", systemImage: "hand.point.up.left.fill") {
            
            // 直接呼叫 AppDelegate 的魔法函數，不再需要廣播了！
            Button(action: {
                appDelegate.openSettingsWindow()
            }) {
                Label("menu_preferences", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("menu_quit", systemImage: "xmark.square")
            }
        }
    }
}
