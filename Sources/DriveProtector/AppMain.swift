import SwiftUI
import AppKit

@main
struct DriveProtectorApp: App {
    @StateObject private var store = MonitorStore()

    init() {
        if CommandLine.arguments.contains("--dump-disks") {
            let raws = IOKitDisk.enumerate()
            print("共检测到 \(raws.count) 块物理磁盘")
            for raw in raws {
                let d = raw.info
                print("""
                      — \(d.bsdName) | \(d.model) | \(d.interconnect) | \
                      \(Fmt.capacity(d.sizeBytes)) | 外接:\(d.isExternal) SSD:\(d.isSSD) | \
                      计数器 R:\(raw.bytesRead) W:\(raw.bytesWritten)
                      """)
                for v in d.volumes {
                    print("    · \(v.name) @ \(v.mountPath)  \(Fmt.capacity(v.totalBytes)) (可用 \(Fmt.capacity(v.availableBytes)))")
                }
            }
            print("smartctl: \(SMARTProvider.smartctlPath ?? "未安装")")
            if let p = SMARTProvider.smartctlPath {
                let inBundle = p.contains("DriveProtector.app") || p.contains("Contents/Resources")
                print("smartctl 来源: \(inBundle ? "App 内置（开箱即用）" : "系统已安装")")
            }
            Foundation.exit(0)
        }
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .frame(minWidth: 1140, minHeight: 720)
                .environmentObject(store)
                .onAppear { store.start() }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))

        // 菜单栏挂件：实时展示各磁盘温度与读写速度
        DriveProtectorMenuBarExtra(store: store)
    }
}
