//
//  SettingsView.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

// MARK: - 面板

/// 设置窗口左侧边栏里的面板。
enum SettingsPane: String, CaseIterable, Identifiable {

    /// UserDefaults / @AppStorage 键。
    ///
    /// 选中项存在这里而不是 `SettingsView` 的 `@State`，是为了让「打开设置并直达某个面板」
    /// 成为可能：菜单里的「管理文件类型…」先把这个键写成 `.newFile` 再开窗，SettingsView
    /// 通过 @AppStorage 读到它就直接落在「创建文件」上。走 @AppStorage 而不是往视图里
    /// 塞一个一次性标记，是因为设置窗口**已经开着**时也要能切过去——@AppStorage 是
    /// SwiftUI 观察得到的依赖，键一变列表选中项就跟着变。
    static let defaultsKey = "settingsPane"

    case general, shortcuts, terminal, editor, newFile, permissions

    /// Swift 不给枚举合成 `id`，必须手写。
    /// 用 `Self`（而不是 `rawValue` 的 String）是为了让 `SettingsPane?` 直接当 List 的选中类型。
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "通用"
        case .shortcuts: return "快捷键"
        case .terminal: return "终端"
        case .editor: return "编辑器"
        case .newFile: return "创建文件"
        case .permissions: return "权限"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .terminal: return "terminal"
        case .editor: return "curlybraces"
        case .newFile: return "doc.badge.plus"
        case .permissions: return "lock.shield"
        }
    }
}

// MARK: - 设置窗口

/// 设置窗口：左侧边栏 + 右侧详情面板。
///
/// **为什么手写 `HStack` 而不是 `NavigationSplitView`**（两个都是实打实的坑，不是偏好）：
///
/// 1. `NavigationSplitView` 会**无条件**往窗口注入 `NSToolbar` 上的 sidebar toggle——而
///    `Settings` 场景本来没有工具栏。`.toolbar(removing:)` 只能删掉那个按钮、删不掉工具栏，
///    而分隔线仍然可以拖拽折叠、删了按钮又没有恢复入口；要彻底禁掉得用 Introspect 去翻
///    `NSSplitViewController` 设 `canCollapse`，本项目零第三方依赖，不值得。
/// 2. Apple 已确认的缺陷 rdar://122947424：detail 列里放固定尺寸内容时，上下会多出等于
///    工具栏高度的空白，`.ignoresSafeArea()` 无效。而 `Settings` 场景是按 `contentSize`
///    决定窗口尺寸的（根视图 ideal size = 窗口大小），这层多余高度会直接让窗口尺寸失控。
///
/// 侧边栏的半透明材质与「内缩圆角矩形」选中高亮，本来就来自 `.listStyle(.sidebar)`
/// ——它是 list 样式的属性，不依赖 `NavigationSplitView`。手写能拿到一样的观感。
struct SettingsView: View {

    @AppStorage("terminalKind") private var terminalKind = 0
    @AppStorage("customTerminalPath") private var customTerminalPath = ""
    @AppStorage("terminalOpenMode") private var terminalOpenMode = 0

    @AppStorage("editorKind") private var editorKind = 0
    @AppStorage("customEditorPath") private var customEditorPath = ""

    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = true
    @AppStorage("menuBarIconStyle") private var menuBarIconStyle = 0

    /// 「创建文件」的类型列表。与菜单栏读写**同一个键**，改动才能双向同步。
    @AppStorage(FileTemplateStore.defaultsKey) private var fileTemplatesJSON = ""

    /// 类型列表的本地编辑态。
    ///
    /// 不直接拿 fileTemplatesJSON 做 Binding：那样每敲一个字符都会写一次 UserDefaults，
    /// 连带菜单内容视图反复重算——`.menuBarExtraStyle(.menu)` 下 ForEach 重渲染有
    /// 「追加而非替换」的已知问题，要尽量少触发。所以本地编辑、防抖写回。
    @State private var templates: [FileTemplate] = []
    /// 防抖任务：连续输入时只保留最后一次写回。
    @State private var templatesSaveTask: Task<Void, Never>?
    /// 最近一次「已同步」的 JSON，用来区分「用户改了」和「onAppear 刚装载」。
    @State private var lastSyncedTemplatesJSON = ""

    /// 侧边栏选中项。存 UserDefaults 而不是 `@State`，这样菜单里的「管理文件类型…」
    /// 能指定打开到哪个面板（原因见 `SettingsPane.defaultsKey`）。
    /// 顺带的效果是设置窗口会记住上次停留的面板，与系统设置的惯例一致。
    @AppStorage(SettingsPane.defaultsKey) private var selectedPaneRaw = SettingsPane.general.rawValue

    /// 把存成字符串的选中项包装回枚举。读取时遇到无法识别的值一律回退「通用」，
    /// 避免将来删掉某个 case 后出现「取消选中、详情区空白」。
    private var selection: Binding<SettingsPane?> {
        Binding(
            get: { SettingsPane(rawValue: selectedPaneRaw) ?? .general },
            set: { selectedPaneRaw = ($0 ?? .general).rawValue }
        )
    }

    @State private var isITermInstalled = TerminalLauncherFactory.isITermInstalled()
    @State private var isCursorInstalled = EditorOpenerFactory.isCursorInstalled()
    @State private var isVSCodeInstalled = EditorOpenerFactory.isVSCodeInstalled()
    /// 必须由本视图持有：`HotkeyRecorder.begin()` 会装一个 NSEvent 本地监听器，
    /// 如果它归某个面板所有，用户正录着快捷键切走面板就会把监听器变成孤儿
    /// （详见 HotkeyRecorder.cancel 的说明）。
    @StateObject private var recorder = HotkeyRecorder()
    /// 观察热键注册结果（共享单例，逐行显示失败/撞车提示）。
    /// 必须用 @ObservedObject 而不是直接访问 `HotkeyManager.shared`，否则 status 变化不会刷新界面。
    @ObservedObject private var hotkeyManager = HotkeyManager.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 捕获设置窗口引用，保证它总是显示在最前面（详见 SettingsOpener）。
        // background 不参与布局，放这里不影响尺寸。
        .background(SettingsWindowCapture())
        // 只加在根上：Settings 场景按根视图的 ideal size 定窗口大小，加在子列上会随面板变化。
        // 也**不要**在外面再套 .padding——那会让 ideal size 变大、窗口比这里写的尺寸还大。
        .frame(width: 720, height: 460)
        .onChange(of: templates) { _, newValue in scheduleSaveTemplates(newValue) }
        .onDisappear {
            // 关窗口时兜底：把最后 400ms 内的编辑写回，并收掉可能还在进行的快捷键录制
            // （否则录制时临时注销的全局热键不会被注册回来）。
            saveTemplatesNow()
            recorder.cancel()
        }
        .onAppear {
            // 同步开机自启状态（用户可能在系统设置里手动改过）。
            launchAtLogin = SMAppService.mainApp.status == .enabled
            // 装载类型列表，并把「当前值」记成已同步，避免刚打开就被当成用户改动写回去。
            templates = FileTemplateStore.templates(from: fileTemplatesJSON)
            lastSyncedTemplatesJSON = FileTemplateStore.encode(
                templates.map { FileTemplateStore.normalize($0) })
            recorder.onRecorded = { hotkey, keyCode, modifiers in
                // GlobalHotkey 的 setter 是 nonmutating 的，直接写 UserDefaults。
                hotkey.keyCode = Int(keyCode)
                hotkey.modifiers = Int(modifiers)
                HotkeyManager.shared.applySettings()
            }
        }
    }

    // MARK: - 侧边栏

    /// `.listStyle(.sidebar)` 是关键：材质与圆角选中高亮都来自它，不加就变成整行蓝色高亮。
    /// 行内容用 `Label` 而不是 `HStack { Image; Text }`——只有 Label/Toggle 在选中态能正确反白。
    private var sidebar: some View {
        List(selection: selection) {
            ForEach(SettingsPane.allCases) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 200)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection.wrappedValue ?? .general {
        case .general: generalPane
        case .shortcuts: shortcutsPane
        case .terminal: terminalPane
        case .editor: editorPane
        case .newFile: newFilePane
        case .permissions: permissionsPane
        }
    }

    /// 面板外壳。统一 `grouped` 表单样式与「放得下就不回弹」的滚动手感。
    ///
    /// 不要在外面再套 `ScrollView`：`Form` 本身就是滚动视图，嵌套会让高度变得不确定，
    /// 反而可能把窗口撑大。
    private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - 通用

    private var generalPane: some View {
        pane {
            Section("菜单栏图标") {
                Picker("图标", selection: $menuBarIconStyle) {
                    Text("应用图标").tag(0)
                    Text("终端图标").tag(1)
                }
                Text("菜单栏显示的图标；默认应用图标，可切换回终端图标。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("启动") {
                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            }

            Section("更新") {
                Toggle("自动检查更新", isOn: $autoCheckUpdates)
                Button("立即检查更新") { AppCommands.shared.checkForUpdates() }
                Text("发现新版本时提示下载。更新源需在发布前替换为自己托管的 JSON（UpdateChecker.feedURL）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 快捷键

    private var shortcutsPane: some View {
        pane {
            Section("全局快捷键") {
                // 每个热键一行：勾选 + 名称 + 录制按钮。两行共用一个 recorder，
                // 靠 recordingTarget 判断当前在录哪个。
                ForEach(GlobalHotkey.allCases) { hotkey in
                    HStack {
                        Toggle("", isOn: enabledBinding(hotkey))
                            .labelsHidden()
                            .toggleStyle(.checkbox)

                        Text(hotkey.title)
                        Spacer()

                        Button(recorder.recordingTarget == hotkey
                               ? "请按下组合键…"
                               : KeycodeTable.displayString(
                                   keyCode: UInt32(hotkey.keyCode),
                                   modifiers: UInt32(hotkey.modifiers))) {
                            recorder.begin(hotkey)
                        }
                        // 已经有一个在录时，只允许操作正在录的那一个。
                        .disabled(recorder.recordingTarget != nil && recorder.recordingTarget != hotkey)
                    }

                    if let message = statusMessage(hotkeyManager.status(of: hotkey)) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // 只提示、不拦截：有报告称 macOS 15 上「只含 ⌥」的全局热键会整体失效
                    // （FB15168205），但不足以据此改掉用户能用的配置。
                    if hotkey.isOptionOnly {
                        Text("只含 ⌥ 的组合在 macOS 15 上有失效报告，若热键无响应建议换一个。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("「打开终端」在 Finder 当前窗口所在目录打开终端。\n「创建文件」不弹窗，直接建一个「未命名」文件并在 Finder 中选中它，可就地改名；类型取你上次用过的那个，可在「创建文件」面板里配置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 用 `GlobalHotkey` 自己读写 UserDefaults 来构造开关绑定。
    ///
    /// 不能像别处那样用 `@AppStorage`：`ForEach` 里没法按变量拼出属性包装器的键。
    /// 开关一改就立刻重新注册；`HotkeyManager.status` 是 @Published，会带动这一行刷新，
    /// 所以绑定的 get 会重新读到新值。
    private func enabledBinding(_ hotkey: GlobalHotkey) -> Binding<Bool> {
        Binding(
            get: { hotkey.isEnabled },
            set: { newValue in
                hotkey.isEnabled = newValue
                HotkeyManager.shared.applySettings()
            }
        )
    }

    /// 注册结果的提示文案；一切正常（或用户主动关闭）时返回 nil。
    private func statusMessage(_ status: GlobalHotkeyStatus) -> String? {
        switch status {
        case .ok, .disabled:
            return nil
        case .duplicate(let other):
            // 必须与「被其它应用占用」区分开：同进程撞车是唯一必然注册失败的情形，
            // 说成「被其它应用占用」会把用户引去换组合键，而真正要改的是另一个热键。
            return "与「\(other.title)」的快捷键重复，请重新录制。"
        case .failed:
            return "注册失败：该组合键可能被系统保留，或已被某个独占注册的 App 占用。"
        }
    }

    // MARK: - 终端

    private var terminalPane: some View {
        pane {
            Section("终端") {
                Picker("打开方式", selection: $terminalKind) {
                    Text("Terminal（系统）").tag(0)
                    if isITermInstalled {
                        Text("iTerm2").tag(1)
                    }
                    Text("自定义…").tag(2)
                }
                .onChange(of: terminalKind) { _, newValue in
                    if newValue == 1 && !isITermInstalled {
                        terminalKind = 0   // iTerm2 未安装则回退
                    }
                }

                if terminalKind == 2 {
                    TextField("终端 App 路径，如 /Applications/kitty.app",
                              text: $customTerminalPath)
                }

                Picker("打开位置", selection: $terminalOpenMode) {
                    Text("新窗口").tag(0)
                    Text("新建标签页").tag(1)
                }

                if terminalKind == 2 {
                    if terminalOpenMode == 1 {
                        Text("自定义终端暂不支持新建标签页，将始终使用新窗口。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // 说明两种模式的语义，避免用户误以为「新建标签页」不会开新窗口。
                    Text(terminalOpenMode == 0
                         ? "总是新建一个终端窗口。"
                         : "没有已打开的终端时新建窗口，已有窗口则在其中新建标签页。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 编辑器

    private var editorPane: some View {
        pane {
            Section("编辑器") {
                Picker("用编辑器打开 Finder 目录", selection: $editorKind) {
                    Text("关闭").tag(0)
                    if isCursorInstalled {
                        Text("Cursor").tag(1)
                    }
                    if isVSCodeInstalled {
                        Text("Visual Studio Code").tag(2)
                    }
                    Text("自定义…").tag(3)
                }
                .onChange(of: editorKind) { _, newValue in
                    if (newValue == 1 && !isCursorInstalled) || (newValue == 2 && !isVSCodeInstalled) {
                        editorKind = 0
                    }
                }

                if editorKind == 3 {
                    TextField("编辑器 App 路径，如 /Applications/Nova.app",
                              text: $customEditorPath)
                }

                if editorKind != 0 {
                    Text("菜单栏将出现「用 \(EditorOpenerFactory.displayName()) 打开」项。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 创建文件

    /// 类型列表做成「表格」：每行结构相同、列宽策略相同（可变列 `maxWidth: .infinity`、
    /// 固定列 `width`），HStack 的分配结果就必然一致，各行天然对齐。
    /// **不要用 `minWidth`**——只给 minWidth 时理想宽度随内容变化，行与行会左右错位。
    private var newFilePane: some View {
        pane {
            Section("创建文件") {
                Text("勾选 = 出现在菜单里；上下顺序即菜单顺序。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach($templates) { $template in
                    HStack(spacing: 8) {
                        Toggle("", isOn: $template.enabled)
                            .labelsHidden()
                            .toggleStyle(.checkbox)

                        // Form 里的 TextField 会把标题渲染成左侧标签，而表格化的行要求
                        // 「勾选框 + 输入框 + 按钮」都待在同一横线上，标签会把每栏挤成上下两行
                        // （扩展名列限宽 64pt，光「扩展名」三个字就占掉约 52pt）。
                        // 所以标题一律用 labelsHidden() 藏掉，只留输入框内的 prompt 提示；
                        // 无障碍标签单独用 accessibilityLabel 补回来。
                        TextField("显示名", text: $template.name, prompt: Text("显示名"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("显示名")

                        // 扩展名不带点，与 FileTemplate 模型、normalizeExtension 的口径一致。
                        TextField("扩展名", text: $template.ext, prompt: Text("md"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 64)
                            .accessibilityLabel("扩展名")

                        // 按钮组整体右对齐，各行位置一致。
                        HStack(spacing: 4) {
                            // `.borderless` 是完全无边框的裸图标，看不出能点；
                            // `.bordered` + `.circle` 才有明显的可点外观。
                            Button { moveTemplate(id: template.id, by: -1) } label: {
                                Image(systemName: "arrow.up").frame(width: 12, height: 12)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .controlSize(.small)
                            .disabled(templates.first?.id == template.id)
                            .help("上移")
                            .accessibilityLabel("上移")

                            Button { moveTemplate(id: template.id, by: 1) } label: {
                                Image(systemName: "arrow.down").frame(width: 12, height: 12)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .controlSize(.small)
                            .disabled(templates.last?.id == template.id)
                            .help("下移")
                            .accessibilityLabel("下移")

                            Button { removeTemplate(id: template.id) } label: {
                                Image(systemName: "trash").frame(width: 12, height: 12)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .controlSize(.small)
                            .help("删除")
                            .accessibilityLabel("删除")
                        }
                    }
                }

                HStack {
                    Button("添加类型") { templates.append(FileTemplate(name: "新类型", ext: "")) }
                    Button("恢复默认列表") { templates = FileTemplateStore.defaultTemplates }
                }

                Text("扩展名不用写点，填完才会出现在菜单里。新增的格式创建空白文件；内置的 docx / xlsx / pptx 会创建可直接打开的空白文档。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 权限

    private var permissionsPane: some View {
        pane {
            Section("权限") {
                Button("打开系统「自动化」授权设置…") {
                    openPrivacySettings("Privacy_Automation")
                }
                Text("读取 Finder 当前目录需要授权本 App 控制 Finder。首次使用时会弹窗询问，误点拒绝后可在这里重新开启。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("打开系统「文件与文件夹」授权设置…") {
                    openPrivacySettings("Privacy_FilesAndFolders")
                }
                Text("「创建文件」会由本 App 直接向你正在浏览的目录写入文件。桌面、文稿、下载受系统保护，若创建失败请在此处允许访问。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 辅助

    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 创建文件：类型列表

    /// 防抖写回。写回前先和 `lastSyncedTemplatesJSON` 比对，值没实际变化就不写。
    ///
    /// 这个比对不是性能优化，是必需的：`onAppear` 装载默认列表也会触发 `onChange`，
    /// 不拦住的话「只是打开了一下设置页」就会把当前默认列表固化进 UserDefaults，
    /// 以后版本新增的默认类型对老用户就再也看不到了。
    private func scheduleSaveTemplates(_ newValue: [FileTemplate]) {
        let json = FileTemplateStore.encode(newValue.map { FileTemplateStore.normalize($0) })
        guard json != lastSyncedTemplatesJSON else { return }

        templatesSaveTask?.cancel()
        templatesSaveTask = Task {
            // 防抖：连续输入时只保留最后一次。这样不会每敲一个字符就写一次
            // UserDefaults、连带菜单内容视图反复重算（`.menu` 样式下 ForEach
            // 重渲染有「追加而非替换」的已知问题，要尽量少触发）。
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            commitTemplates(json)
        }
    }

    /// 立即写回。关闭设置窗口时兜底，避免丢掉最后 400ms 内的输入。
    private func saveTemplatesNow() {
        templatesSaveTask?.cancel()
        templatesSaveTask = nil

        let json = FileTemplateStore.encode(templates.map { FileTemplateStore.normalize($0) })
        guard json != lastSyncedTemplatesJSON else { return }
        commitTemplates(json)
    }

    private func commitTemplates(_ json: String) {
        lastSyncedTemplatesJSON = json
        fileTemplatesJSON = json
    }

    /// 上移 / 下移。按 id 定位而不是记下标：`ForEach($array)` 里行内改元素时，
    /// SwiftUI 内部仍持有按下标的绑定，按 id 找更稳。`swapAt` 不改变元素总数，也最安全。
    private func moveTemplate(id: UUID, by offset: Int) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard templates.indices.contains(target) else { return }
        templates.swapAt(index, target)
    }

    /// 删除。同样按 id 定位——`ForEach($array)` 行内按下标删元素有已知的越界崩溃。
    private func removeTemplate(id: UUID) {
        templates.removeAll { $0.id == id }
    }

    // MARK: - 开机自启

    /// 注册 / 注销登录项。需要 App 位于 /Applications 且签名有效。
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[LXFinderLauncher] 设置开机自启失败：\(error)")
        }
    }
}
