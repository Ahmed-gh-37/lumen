import AppKit
import Carbon
import Combine
import LumenCore
import SwiftUI

@main
struct LumenApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

final class OverlayPanel: NSPanel {
    var attachedToNotch = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        attachedToNotch ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel?
    private var panel: OverlayPanel?
    private var statusItem: NSStatusItem?
    private var hotKeys: HotKeys?
    private var preferences: AnyCancellable?
    private var mouseEvents: AnyCancellable?
    private var mouseMenuItem: NSMenuItem?
    private var automaticMenuItem: NSMenuItem?
    private var automaticEvents: AnyCancellable?
    private var presentation: AnyCancellable?
    private var readerActivity: AnyCancellable?
    private var screenChanges: AnyCancellable?
    private var notchMenuItem: NSMenuItem?
    private var floatingFrame: NSRect?
    private var notchApplied = false
    private var notchScreenID: CGDirectDisplayID?
    private var collapseTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let model = try AppModel(directory: support.appendingPathComponent("Lumen", isDirectory: true))
            self.model = model
            let panel = OverlayPanel(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 740),
                styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
            panel.title = "Lumen"
            panel.minSize = NSSize(width: 480, height: 580)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.isMovableByWindowBackground = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            let hosting = OverlayHostingView(rootView: RootView(model: model))
            hosting.sizingOptions = []
            hosting.onHoverChange = { [weak self] entered in self?.hoverChanged(entered) }
            panel.contentView = hosting
            panel.delegate = self
            panel.setFrameAutosaveName("LumenOverlay")
            if !panel.setFrameUsingName("LumenOverlay"), let screen = NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: frame.maxX - 590, y: max(frame.minY + 20, frame.maxY - 770)))
            }
            self.panel = panel
            model.hideWindow = { [weak self] in self?.hideWindow(nil) }
            preferences = model.$data.map(\.preferences).removeDuplicates().sink { [weak panel] settings in
                panel?.alphaValue = max(0.45, min(1, settings.opacity))
                panel?.sharingType = settings.protectCapture ? .none : .readOnly
            }
            installMenu()
            mouseEvents = model.$mousePassthrough.removeDuplicates().sink { [weak self, weak panel] enabled in
                panel?.ignoresMouseEvents = enabled
                if enabled { panel?.resignKey() }
                self?.mouseMenuItem?.state = enabled ? .on : .off
            }
            automaticEvents = model.$automaticScreenState.removeDuplicates().sink { [weak self] state in
                self?.automaticMenuItem?.title =
                    state.isRunning
                    ? "Stop automatic screen explanations (\(state.sentCount)/60)"
                    : "Start automatic screen explanations"
            }
            presentation = Publishers.CombineLatest4(
                model.$data.map(\.preferences).removeDuplicates(), model.$notchExpanded.removeDuplicates(),
                model.$page.removeDuplicates(), model.$teleprompterEditing.removeDuplicates()
            )
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.applyPanelPresentation(animated: true) }
            readerActivity = Publishers.CombineLatest4(
                model.$teleprompterRunning, model.$teleprompterStarting, model.$recordingShortcut, model.$notchSizing
            )
            .receive(on: RunLoop.main).sink { [weak self, weak model] _ in
                guard let self, let model, model.notchSettings.enabled else { return }
                if model.notchHeldOpen {
                    self.collapseTask?.cancel()
                    model.notchExpanded = true
                } else {
                    self.scheduleCollapse()
                }
            }
            screenChanges = NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
            .sink { [weak self] _ in self?.applyPanelPresentation(animated: false) }
            let configured = Dictionary(
                uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, model.data.preferences.shortcut(for: $0)) })
            hotKeys = HotKeys(bindings: configured) { [weak self] action in
                guard let self, let model = self.model else { return }
                switch action {
                case .toggleOverlay: self.toggleWindow(nil)
                case .ask:
                    model.page = .ask
                    self.showWindow(nil)
                case .listen:
                    model.toggleListening()
                    self.presentOverlay()
                case .notes:
                    model.page = .notes
                    self.showWindow(nil)
                case .captureScreen:
                    model.captureScreen()
                    self.presentOverlay()
                case .explainScreen:
                    model.explainScreen()
                    self.presentOverlay()
                case .clickThrough: self.toggleMouseInteraction(nil)
                case .automaticScreen: self.toggleAutomaticScreens(nil)
                case .teleprompter:
                    model.toggleTeleprompter()
                    self.presentOverlay()
                }
            }
            let failures = hotKeys?.register() ?? []
            if !failures.isEmpty { model.error = failures.joined(separator: "\n") }
            model.applyShortcut = { [weak self] action, binding in
                self?.hotKeys?.replace(action, with: binding)
            }
            model.shortcutRecordingChanged = { [weak self, weak model] suspended in
                let failures = self?.hotKeys?.setSuspended(suspended) ?? []
                if !failures.isEmpty { model?.error = failures.joined(separator: "\n") }
            }
            if model.notchSettings.enabled {
                applyPanelPresentation(animated: false)
                panel.orderFrontRegardless()
            } else {
                showWindow(nil)
            }
            model.refreshAccount()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Lumen could not open its local workspace"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Lumen")
        item.button?.title = " Lumen"
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Lumen", action: #selector(showWindow(_:)), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let hide = NSMenuItem(title: "Hide Lumen", action: #selector(hideWindow(_:)), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        let notch = NSMenuItem(title: "Attach to notch", action: #selector(toggleNotchMode(_:)), keyEquivalent: "")
        notch.target = self
        menu.addItem(notch)
        notchMenuItem = notch
        let note = NSMenuItem(title: "New Note", action: #selector(newNote(_:)), keyEquivalent: "")
        note.target = self
        menu.addItem(note)
        let prompter = NSMenuItem(
            title: "Teleprompter play or pause", action: #selector(toggleTeleprompter(_:)), keyEquivalent: "")
        prompter.target = self
        menu.addItem(prompter)
        let mouse = NSMenuItem(
            title: "Mouse click-through", action: #selector(toggleMouseInteraction(_:)), keyEquivalent: "")
        mouse.target = self
        menu.addItem(mouse)
        mouseMenuItem = mouse
        let automatic = NSMenuItem(
            title: "Start automatic screen explanations", action: #selector(toggleAutomaticScreens(_:)),
            keyEquivalent: "")
        automatic.target = self
        menu.addItem(automatic)
        automaticMenuItem = automatic
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Lumen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }
    private func presentOverlay() {
        if model?.notchSettings.enabled == true {
            model?.notchExpanded = true
            applyPanelPresentation(animated: false)
        }
        if model?.mousePassthrough == true {
            panel?.orderFrontRegardless()
        } else {
            panel?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    @objc private func showWindow(_ sender: Any?) {
        model?.mousePassthrough = false
        presentOverlay()
    }
    @objc private func hideWindow(_ sender: Any?) {
        model?.pauseTeleprompter()
        panel?.orderOut(nil)
    }
    @objc private func toggleWindow(_ sender: Any?) {
        if panel?.isVisible == true { hideWindow(sender) } else { presentOverlay() }
    }
    @objc private func toggleMouseInteraction(_ sender: Any?) {
        model?.cancelShortcutRecording()
        model?.mousePassthrough.toggle()
    }
    @objc private func toggleAutomaticScreens(_ sender: Any?) {
        model?.toggleAutomaticScreens()
        if model?.automaticScreenState.isRunning == true { presentOverlay() }
    }
    @objc private func newNote(_ sender: Any?) {
        model?.newNote()
        showWindow(sender)
    }
    @objc private func toggleTeleprompter(_ sender: Any?) {
        model?.toggleTeleprompter()
        showWindow(sender)
    }
    @objc private func toggleNotchMode(_ sender: Any?) {
        model?.toggleNotchMode()
        showWindow(sender)
    }

    private func hoverChanged(_ entered: Bool) {
        guard let model, model.notchSettings.enabled else { return }
        if entered {
            collapseTask?.cancel()
            model.notchExpanded = true
        } else {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        guard model?.notchSettings.enabled == true else { return }
        collapseTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
            guard let self, let model = self.model, let panel = self.panel,
                model.notchSettings.enabled, !model.notchHeldOpen, !panel.isKeyWindow,
                !NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
            else { return }
            model.notchExpanded = false
        }
    }

    private func applyPanelPresentation(animated: Bool) {
        guard let model, let panel else { return }
        notchMenuItem?.state = model.notchSettings.enabled ? .on : .off
        notchMenuItem?.title = model.notchSettings.enabled ? "Return to floating window" : "Attach to notch"
        guard model.notchSettings.enabled else {
            guard notchApplied else { return }
            collapseTask?.cancel()
            notchApplied = false
            panel.attachedToNotch = false
            panel.styleMask.insert(.resizable)
            panel.minSize = NSSize(width: 480, height: 580)
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            if var frame = floatingFrame,
                let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) })
                    ?? NSScreen.main
            {
                let visible = screen.visibleFrame
                frame.size = NSSize(width: min(frame.width, visible.width), height: min(frame.height, visible.height))
                frame.origin.x = min(max(visible.minX, frame.minX), visible.maxX - frame.width)
                frame.origin.y = min(max(visible.minY, frame.minY), visible.maxY - frame.height)
                panel.setFrame(frame, display: true)
            }
            panel.setFrameAutosaveName("LumenOverlay")
            return
        }
        if !notchApplied {
            floatingFrame = panel.frame
            notchScreenID =
                (panel.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            panel.setFrameAutosaveName("")
            panel.attachedToNotch = true
            panel.minSize = .zero
            panel.styleMask.remove(.resizable)
            panel.isMovableByWindowBackground = false
            notchApplied = true
        }
        guard
            let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                    == notchScreenID
            }) ?? NSScreen.main
        else { return }
        let topInset = max(28, screen.safeAreaInsets.top)
        let left = screen.auxiliaryTopLeftArea ?? .zero
        let right = screen.auxiliaryTopRightArea ?? .zero
        let hasCamera = !left.isEmpty && !right.isEmpty && right.minX > left.maxX
        let cameraWidth = hasCamera ? right.minX - left.maxX : 94
        let cameraCenterX = hasCamera ? (left.maxX + right.minX) / 2 : screen.frame.midX
        if model.notchTopInset != topInset { model.notchTopInset = topInset }
        if model.notchCameraWidth != cameraWidth { model.notchCameraWidth = cameraWidth }
        let bodyHeight =
            model.notchReading
            ? NotchGeometry.readingBodyHeight(
                fontSize: model.teleprompterSettings.fontSize, lines: model.notchSettings.readingLines)
            : min(700, max(480, screen.frame.height - topInset - 40))
        let frame = NotchGeometry.frame(
            screen: screen.frame, cameraCenterX: cameraCenterX, cameraWidth: cameraWidth,
            topInset: topInset, expanded: model.notchExpanded,
            preferredWidth: model.notchSettings.width, bodyHeight: bodyHeight)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        guard panel.frame != frame else { return }
        if animated && panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        if model.notchExpanded { scheduleCollapse() }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        collapseTask?.cancel()
        if model?.notchSettings.enabled == true { model?.notchExpanded = true }
    }
    func windowDidResignKey(_ notification: Notification) { scheduleCollapse() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(nil)
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        collapseTask?.cancel()
        model?.shutdown()
    }
}

@MainActor
final class HotKeys {
    private var handler: EventHandlerRef?
    private var references: [ShortcutAction: EventHotKeyRef] = [:]
    private var bindings: [ShortcutAction: ShortcutBinding]
    private var suspended = false
    private var handlerStatus: OSStatus = noErr
    private let action: (ShortcutAction) -> Void
    init(bindings: [ShortcutAction: ShortcutBinding], action: @escaping (ShortcutAction) -> Void) {
        self.bindings = bindings
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr, identifier.signature == 0x4c55_4d4e else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
                guard let action = ShortcutAction.allCases.first(where: { $0.hotKeyID == identifier.id }) else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async { owner.action(action) }
                return noErr
            }, 1, &type, context, &handler)
    }
    func register() -> [String] {
        guard handlerStatus == noErr else { return ["Global shortcuts are unavailable (macOS code \(handlerStatus))."] }
        guard !suspended else { return [] }
        var failures: [String] = []
        for action in ShortcutAction.allCases where references[action] == nil {
            let binding = bindings[action] ?? action.defaultBinding
            guard binding.keyCode != nil else { continue }
            let (reference, status) = registerBinding(binding, for: action)
            if let reference, status == noErr {
                references[action] = reference
            } else {
                failures.append(unavailableMessage(binding, action: action, status: status))
            }
        }
        return failures
    }
    func setSuspended(_ value: Bool) -> [String] {
        guard suspended != value else { return [] }
        suspended = value
        if value {
            for reference in references.values { UnregisterEventHotKey(reference) }
            references.removeAll()
            return []
        }
        return register()
    }
    func replace(_ action: ShortcutAction, with binding: ShortcutBinding) -> String? {
        guard handlerStatus == noErr else { return "Global shortcuts are unavailable (macOS code \(handlerStatus))." }
        if let current = bindings[action], current.conflicts(with: binding), references[action] != nil {
            bindings[action] = binding
            return nil
        }
        if suspended {
            bindings[action] = binding
            return nil
        }
        guard binding.keyCode != nil else {
            if let old = references.removeValue(forKey: action) { UnregisterEventHotKey(old) }
            bindings[action] = binding
            return nil
        }
        // Register the replacement first. A conflict leaves the previous shortcut active.
        let (reference, status) = registerBinding(binding, for: action)
        guard status == noErr, let reference else { return unavailableMessage(binding, action: action, status: status) }
        if let old = references[action] { UnregisterEventHotKey(old) }
        references[action] = reference
        bindings[action] = binding
        return nil
    }
    private func registerBinding(_ binding: ShortcutBinding, for action: ShortcutAction) -> (EventHotKeyRef?, OSStatus)
    {
        guard let key = binding.keyCode else { return (nil, noErr) }
        var flags: UInt32 = 0
        if binding.modifiers & 1 != 0 { flags |= UInt32(cmdKey) }
        if binding.modifiers & 2 != 0 { flags |= UInt32(optionKey) }
        if binding.modifiers & 4 != 0 { flags |= UInt32(shiftKey) }
        if binding.modifiers & 8 != 0 { flags |= UInt32(controlKey) }
        var reference: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x4c55_4d4e, id: action.hotKeyID)
        let status = RegisterEventHotKey(key, flags, id, GetApplicationEventTarget(), 0, &reference)
        return (reference, status)
    }
    private func unavailableMessage(_ binding: ShortcutBinding, action: ShortcutAction, status: OSStatus) -> String {
        "\(binding.display) for \(action.title) is unavailable (macOS code \(status)). macOS or another app may already use it. Choose a different shortcut in Settings."
    }
    deinit {
        for reference in references.values { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
