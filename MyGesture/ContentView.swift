import SwiftUI
import AppKit
import OpenMultitouchSupport
import CoreGraphics
import ApplicationServices
import Combine // 🌟 修正：加入 Combine 以確保 ObservableObject 協議正常運作

@MainActor
class GestureManager: ObservableObject {
    let manager = OMSManager.shared
    
    // 🌟 加一個 @Published 確保編譯器能自動合成 ObservableObject 需要的底層程式碼
    @Published var isListening = false
    
    var activeTouches:[Int32: OMSTouchData] = [:]
    var startPositions:[Int32: OMSPosition] = [:]
    var maxFingersInCurrentGesture = 0
    var isSwiping = false
    var gestureStartTime: Date? // 🌟 記錄手勢開始時間
    
    init() {
        Task {
            for await touches in manager.touchDataStream {
                for touch in touches {
                    processTouch(touch)
                }
            }
        }
        setupWakeListener() // 啟動睡眠喚醒/解鎖的「鬧鐘」
    }
    
    func start() {
        manager.startListening()
        isListening = true
    }
    
    func restart() {
        manager.stopListening()
        isListening = false
        // 延遲兩秒等系統的觸控板硬體完全啟動後，再重新連線
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.manager.startListening()
            self.isListening = true
        }
    }
    
    func setupWakeListener() {
        let nc = NSWorkspace.shared.notificationCenter
        
        // 1. 監聽電腦睡醒
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            // 🌟 修正警告：確保在 MainActor 執行
            Task { @MainActor in
                self.restart()
            }
        }
        
        // 2. 監聽螢幕解鎖 (🌟 修正錯誤三：使用 DistributedNotificationCenter)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                self.restart()
            }
        }
    }
    
    // 讀取偏好設定的開關狀態
    func isEnabled(_ key: String) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(true, forKey: key) // 預設為開啟
        }
        return UserDefaults.standard.bool(forKey: key)
    }
    
    func processTouch(_ touch: OMSTouchData) {
        let state = touch.state
        
        if state == .starting || state == .making {
            if activeTouches.isEmpty {
                gestureStartTime = Date() // 🌟 開始計時
            }
            activeTouches[touch.id] = touch
            startPositions[touch.id] = touch.position
            if activeTouches.count > maxFingersInCurrentGesture {
                maxFingersInCurrentGesture = activeTouches.count
            }
        }
        else if state == .touching || state == .lingering {
            activeTouches[touch.id] = touch
            if maxFingersInCurrentGesture == 3 {
                var totalDeltaY: Float = 0
                for (id, currentTouch) in activeTouches {
                    if let start = startPositions[id] {
                        totalDeltaY += (currentTouch.position.y - start.y)
                    }
                }
                let avgDeltaY = totalDeltaY / 3.0
                
                // 🌟 改變 1: 拉長判定距離，並且這裡只做標記不執行
                if avgDeltaY < -0.10 && !isSwiping {
                    isSwiping = true
                }
            }
        }
        else if state == .breaking || state == .leaving || state == .notTouching {
            activeTouches.removeValue(forKey: touch.id)
            if activeTouches.isEmpty {
                let duration = Date().timeIntervalSince(gestureStartTime ?? Date())
                
                if !isSwiping {
                    if duration < 0.25 { // 🌟 限制 250ms 內完成才算輕觸
                        if maxFingersInCurrentGesture == 3 {
                            if isEnabled("enableMiddleClick") { simulateMiddleClick() }
                        } else if maxFingersInCurrentGesture == 4 {
                            if isEnabled("enableMaximize") { maximizeFocusedWindow() }
                        }
                    }
                } else {
                    // 🌟 改變 2: 手指抬起且剛剛有達成滑動距離時，才執行 ESC，並且要在一定時間內完成！
                    // 限制 0.4 秒，代表從放上手指到往下滑並離開觸控板，必須在該秒內完成。
                    // 這樣就可以防止手指一直放在觸控板上、不小心微微往下滑而意外關閉預覽的情況。
                    if maxFingersInCurrentGesture == 3 && duration < 0.4 {
                        if isEnabled("enableCmdW") { simulateCmdW() }
                    }
                }
                maxFingersInCurrentGesture = 0
                startPositions.removeAll()
                isSwiping = false
                gestureStartTime = nil // 🌟 清除計時
            }
        }
    }
    
    // --- 動作實作區 ---
    func simulateMiddleClick() {
        guard let currentEvent = CGEvent(source: nil) else { return }
        let loc = currentEvent.location
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(mouseEventSource: src, mouseType: .otherMouseDown, mouseCursorPosition: loc, mouseButton: .center)
        let up = CGEvent(mouseEventSource: src, mouseType: .otherMouseUp, mouseCursorPosition: loc, mouseButton: .center)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
    
    func simulateCmdW() {
        let src = CGEventSource(stateID: .hidSystemState)
        // virtualKey 13 is 'W'
        let down = CGEvent(keyboardEventSource: src, virtualKey: 13, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 13, keyDown: false)
        
        // 加上 Command 鍵的作用
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
    
    func maximizeFocusedWindow() {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard let app = focusedApp else { return }
        
        var focusedWindow: CFTypeRef?
        AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard let window = focusedWindow else { return }
        let axWindow = window as! AXUIElement
        
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let screenHeight = screen.frame.height
        
        let cgY = screenHeight - visibleFrame.maxY
        var newPosition = CGPoint(x: visibleFrame.minX, y: cgY)
        var newSize = CGSize(width: visibleFrame.width, height: visibleFrame.height)
        
        guard let positionValue = AXValueCreate(.cgPoint, &newPosition),
              let sizeValue = AXValueCreate(.cgSize, &newSize) else { return }
        
        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
    }
}

// --- 介面設計 ---
struct ContentView: View {
    @ObservedObject var gestureManager: GestureManager
    @State var hasPermission = false
    
    @AppStorage("enableMiddleClick") var enableMiddleClick = true
    @AppStorage("enableCmdW") var enableCmdW = true
    @AppStorage("enableMaximize") var enableMaximize = true
    
    var body: some View {
        Form {
            Section {
                if !hasPermission {
                    HStack {
                        Text("permission_required_message")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("permission_open_settings") {
                            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                            _ = AXIsProcessTrustedWithOptions(options)
                        }
                    }
                } else {
                    HStack {
                        Text("permission_status_label")
                        Spacer()
                        Text("permission_status_granted")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section {
                Toggle(isOn: $enableMiddleClick) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("gesture_3tap_title")
                        Text("gesture_3tap_desc")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: $enableCmdW) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("gesture_3swipe_down_title")
                        Text("gesture_3swipe_down_desc")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: $enableMaximize) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("gesture_4tap_title")
                        Text("gesture_4tap_desc")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 320)
        .navigationTitle("app_name")
        .onAppear {
            NSApp.activate(ignoringOtherApps: true) // 🌟 讓視窗一打開就強制顯示在最前面
            hasPermission = AXIsProcessTrusted()
            if hasPermission { gestureManager.start() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let currentPermission = AXIsProcessTrusted()
            if currentPermission != hasPermission {
                hasPermission = currentPermission
                if hasPermission && !gestureManager.isListening {
                    gestureManager.start()
                }
            }
        }
    }
}
