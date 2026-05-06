import SwiftUI
import AppKit
import OpenMultitouchSupport
import CoreGraphics
import ApplicationServices
import Combine

@MainActor
class GestureManager: ObservableObject {
    let manager = OMSManager.shared
    var activeTouches: [Int32: OMSTouchData] = [:]
    var startPositions:[Int32: OMSPosition] = [:]
    var maxFingersInCurrentGesture = 0
    var isSwiping = false
    
    @Published var lastAction: String = "等待手勢中..."
    
    init() {
        Task {
            // 現在工具箱會一次丟出「一包」手指 (touches)
            for await touches in manager.touchDataStream {
                // 我們把它打開，一根一根拿出來處理
                for touch in touches {
                    processTouch(touch)
                }
            }
        }
    }
    
    func start() {
        manager.startListening()
        lastAction = "✅ 已經開始監聽觸控板！試試看手勢吧！"
    }
    
    func processTouch(_ touch: OMSTouchData) {
        let state = touch.state
        
        // 手指剛放上去
        if state == .starting || state == .making {
            activeTouches[touch.id] = touch
            startPositions[touch.id] = touch.position
            if activeTouches.count > maxFingersInCurrentGesture {
                maxFingersInCurrentGesture = activeTouches.count
            }
        }
        // 手指在滑動或停留在上面
        else if state == .touching || state == .lingering {
            activeTouches[touch.id] = touch
            
            // 偵測三指下滑 (y座標變小)
            if maxFingersInCurrentGesture == 3 {
                var totalDeltaY: Float = 0
                for (id, currentTouch) in activeTouches {
                    if let start = startPositions[id] {
                        totalDeltaY += (currentTouch.position.y - start.y)
                    }
                }
                // 算出平均移動距離
                let avgDeltaY = totalDeltaY / 3.0
                
                // 如果往下超過一定距離，且還沒觸發過滑動 (-0.05 是滑動靈敏度，可調整)
                if avgDeltaY < -0.05 && !isSwiping {
                    isSwiping = true
                    self.lastAction = "🚀 偵測到：三指下滑 (執行 Esc)"
                    simulateEscKey()
                }
            }
        }
        // 手指離開
        else if state == .breaking || state == .leaving || state == .notTouching {
            activeTouches.removeValue(forKey: touch.id)
            
            // 當所有手指都離開時，判斷是不是「輕觸」
            if activeTouches.isEmpty {
                if !isSwiping {
                    if maxFingersInCurrentGesture == 3 {
                        self.lastAction = "🖱️ 偵測到：三指輕觸 (執行滑鼠中鍵)"
                        simulateMiddleClick()
                    } else if maxFingersInCurrentGesture == 4 {
                        self.lastAction = "🟩 偵測到：四指輕觸 (執行 Option+綠色按鈕)"
                        maximizeFocusedWindow()
                    }
                }
                // 重置手勢狀態，準備迎接下一次
                maxFingersInCurrentGesture = 0
                startPositions.removeAll()
                isSwiping = false
            }
        }
    }
    
    // --- 下面是動作實作區 ---
    
    // 1. 模擬滑鼠中鍵
    func simulateMiddleClick() {
        guard let currentEvent = CGEvent(source: nil) else { return }
        let loc = currentEvent.location
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(mouseEventSource: src, mouseType: .otherMouseDown, mouseCursorPosition: loc, mouseButton: .center)
        let up = CGEvent(mouseEventSource: src, mouseType: .otherMouseUp, mouseCursorPosition: loc, mouseButton: .center)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
    
    // 2. 模擬按下 Esc
    func simulateEscKey() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
    
    // 3. 將當前視窗最大化 (不進入全螢幕)
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

// --- 下面是軟體視窗的介面設計 ---
struct ContentView: View {
    @StateObject var gestureManager = GestureManager()
    @State var hasPermission = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🖐️ 我的手勢")
                .font(.largeTitle)
                .bold()
            
            if !hasPermission {
                Text("需要輔助使用權限才能控制滑鼠與鍵盤")
                    .foregroundColor(.red)
                
                Button("點我開啟權限設定") {
                    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    _ = AXIsProcessTrustedWithOptions(options)
                }
                .buttonStyle(.borderedProminent) // 使用 Mac 原生的顯眼藍色按鈕風格
                .controlSize(.large) // 把按鈕稍微放大一點比較好點
                
                Text("開啟後，請重開這個 App (按左上角的 Stop 再按 Play)")
                    .font(.footnote)
                    .foregroundColor(.gray)
            } else {
                Text(gestureManager.lastAction)
                    .font(.title2)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
        .onAppear {
            hasPermission = AXIsProcessTrusted()
            if hasPermission {
                gestureManager.start()
            }
        }
    }
}
