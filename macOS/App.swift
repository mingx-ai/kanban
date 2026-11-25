import AppKit
import UniformTypeIdentifiers
import WebKit

private struct WorkspaceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

private final class WorkspaceController: NSObject, NSApplicationDelegate, WKNavigationDelegate, NSMenuItemValidation {
    private let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "个人任务工作台"
    private var window: NSWindow!
    private var webView: WKWebView!
    private var workspaceURL: URL?
    private var pageReady = false
    private var transferInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenus()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.addUserScript(WKUserScript(source: """
        window.isKanbanMacApp = true;
        if (typeof crypto.randomUUID !== 'function') {
          Object.defineProperty(crypto, 'randomUUID', { value() {
            const bytes = crypto.getRandomValues(new Uint8Array(16));
            bytes[6] = (bytes[6] & 15) | 64;
            bytes[8] = (bytes[8] & 63) | 128;
            const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
            return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join('-');
          } });
        }
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false

        let bounds = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let size = NSSize(width: min(1280, bounds.width), height: min(840, max(460, bounds.height - 50)))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = appName
        window.minSize = NSSize(width: 420, height: 360)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.center()
        window.setFrameAutosaveName("WorkspaceMainWindow")
        presentWindow()
        do {
            workspaceURL = try prepareWorkspace()
            loadWorkspace()
        } catch {
            showError("无法打开工作台", error)
        }
    }

    private func prepareWorkspace() throws -> URL {
        guard let source = Bundle.main.url(forResource: "workspace", withExtension: "html"),
              let identifier = Bundle.main.bundleIdentifier else {
            throw WorkspaceError("应用包缺少工作台页面或应用标识。")
        }
        let files = FileManager.default
        let support = try files.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent(identifier, isDirectory: true).appendingPathComponent("Web", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // The file's origin stays stable when the user moves or updates the application bundle.
        let destination = directory.appendingPathComponent("workspace.html")
        var html = try String(contentsOf: source, encoding: .utf8)
        guard let head = html.range(of: "<head>", options: .caseInsensitive) else {
            throw WorkspaceError("工作台页面格式无效。")
        }
        let policy = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'"
        html.insert(contentsOf: "<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">", at: head.upperBound)
        let data = Data(html.utf8)
        if (try? Data(contentsOf: destination)) != data {
            try data.write(to: destination, options: .atomic)
        }
        return destination
    }

    private func loadWorkspace() {
        guard let url = workspaceURL else { return }
        pageReady = false
        webView.loadFileURL(url, allowingReadAccessTo: url)
    }

    private func isTrusted(_ url: URL?) -> Bool {
        guard let url, let expected = workspaceURL, url.isFileURL,
              url.host == nil || url.host == "" || url.host == "localhost" else { return false }
        return url.standardizedFileURL.path == expected.standardizedFileURL.path
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = navigationAction.targetFrame?.isMainFrame == true && isTrusted(navigationAction.request.url)
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = isTrusted(webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showError("无法载入工作台", error) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadWorkspace()
    }

    private func presentWindow() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentWindow()
        return true
    }

    private func configureMenus() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            entry.submenu = menu
            main.addItem(entry)
            return menu
        }
        let app = submenu(appName)
        app.addItem(withTitle: "关于\(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "隐藏\(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "退出\(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = submenu("文件")
        file.addItem(withTitle: "新建任务", action: #selector(newTask(_:)), keyEquivalent: "n").target = self
        file.addItem(.separator())
        file.addItem(withTitle: "导入工作台备份…", action: #selector(importBackup(_:)), keyEquivalent: "").target = self
        file.addItem(withTitle: "导出工作台备份…", action: #selector(exportBackup(_:)), keyEquivalent: "").target = self
        file.addItem(.separator())
        file.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = submenu("编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let windows = submenu("窗口")
        windows.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windows
        NSApp.mainMenu = main
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        pageReady && !transferInProgress && window?.attachedSheet == nil
    }

    @objc private func newTask(_ sender: Any?) {
        guard pageReady, !transferInProgress else { return }
        presentWindow()
        webView.evaluateJavaScript("if (!document.querySelector('dialog[open]')) document.getElementById('new-task')?.click();")
    }

    @objc private func exportBackup(_ sender: Any?) {
        guard pageReady, !transferInProgress else { return }
        presentWindow()
        transferInProgress = true
        let panel = NSSavePanel()
        panel.title = "导出工作台备份"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let date = DateFormatter()
        date.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "工作台备份-\(date.string(from: Date())).json"
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let url = panel.url else { transferInProgress = false; return }
            guard pageReady, isTrusted(webView.url) else { transferInProgress = false; return }
            webView.callAsyncJavaScript("return await window.kanbanTransfer.exportBackup();", arguments: [:], in: nil, in: .page) { [self] result in
                defer { transferInProgress = false }
                do {
                    guard let text = try result.get() as? String else { throw WorkspaceError("工作台没有返回有效的备份。") }
                    try Data(text.utf8).write(to: url, options: .atomic)
                } catch { showError("无法导出备份", error) }
            }
        }
    }

    @objc private func importBackup(_ sender: Any?) {
        guard pageReady, !transferInProgress else { return }
        presentWindow()
        transferInProgress = true
        let panel = NSOpenPanel()
        panel.title = "导入工作台备份"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let url = panel.url else { transferInProgress = false; return }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                inspectImport(text, fileName: url.lastPathComponent)
            } catch {
                transferInProgress = false
                showError("无法读取备份", error)
            }
        }
    }

    private func inspectImport(_ text: String, fileName: String) {
        guard pageReady, isTrusted(webView.url) else { transferInProgress = false; return }
        webView.callAsyncJavaScript("return await window.kanbanTransfer.inspectBackup(text);", arguments: ["text": text], in: nil, in: .page) { [self] result in
            do {
                guard let counts = try result.get() as? [String: Any],
                      let tasks = counts["tasks"] as? Int, let groups = counts["groups"] as? Int,
                      let archive = counts["archive"] as? Int else { throw WorkspaceError("无法识别备份内容。") }
                let summary = "备份含 \(tasks) 项活动任务、\(groups) 个分组和 \(archive) 项归档。"
                confirmImport(text, fileName: fileName, summary: summary)
            } catch {
                transferInProgress = false
                showError("无法读取备份", error)
            }
        }
    }

    private func confirmImport(_ text: String, fileName: String, summary: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "用备份替换当前工作台？"
        alert.informativeText = "\(summary) 导入「\(fileName)」将替换当前工作台的数据。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "导入并替换")
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertSecondButtonReturn, pageReady, isTrusted(webView.url) else {
                transferInProgress = false
                return
            }
            webView.callAsyncJavaScript("return await window.kanbanTransfer.importBackup(text);", arguments: ["text": text], in: nil, in: .page) { [self] result in
                defer { transferInProgress = false }
                do {
                    guard try result.get() as? Bool == true else { throw WorkspaceError("工作台未能导入备份。") }
                    loadWorkspace()
                } catch { showError("无法导入备份", error) }
            }
        }
    }

    private func showError(_ title: String, _ error: Error) {
        let info = error as NSError
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = info.userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window)
    }
}

@main
private struct WorkspaceApplication {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let controller = WorkspaceController()
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}
