import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var dial: VolumeDial

    var body: some View {
        TabView {
            FeelTab(settings: settings, dial: dial)
                .tabItem { Label("Feel", systemImage: "dial.medium") }
            AppsTab(settings: settings)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
        }
        .frame(width: 440, height: 400)
    }
}

private struct FeelTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject var dial: VolumeDial

    var body: some View {
        Form {
            Section {
                Toggle("Twist two fingers to set the volume", isOn: $settings.isEnabled)
                Toggle("Reverse direction", isOn: $settings.invertDirection)
                    .help("By default, clockwise raises the volume.")
            }

            Section("Sensitivity") {
                Slider(value: $settings.degreesForFullSweep, in: 30...180, step: 5) {
                    Text("Full sweep")
                } minimumValueLabel: {
                    Text("30°").font(.caption2)
                } maximumValueLabel: {
                    Text("180°").font(.caption2)
                }
                LabeledContent("Silent to full",
                               value: "\(Int(settings.degreesForFullSweep))° of twist")

                Slider(value: $settings.activationThreshold, in: 4...30, step: 1) {
                    Text("Dead zone")
                } minimumValueLabel: {
                    Text("4°").font(.caption2)
                } maximumValueLabel: {
                    Text("30°").font(.caption2)
                }
                LabeledContent("Ignored at the start",
                               value: "\(Int(settings.activationThreshold))°")

                LabeledContent("Twisting now") {
                    Text(dial.isEngaged ? "\(Int(abs(dial.liveTwistDegrees)))°" : "—")
                        .monospacedDigit()
                        .foregroundStyle(dial.isEngaged ? .primary : .secondary)
                }
            }

            Section("Detents") {
                Picker("Steps", selection: $settings.detentCount) {
                    Text("Smooth").tag(0)
                    Text("8").tag(8)
                    Text("16").tag(16)
                    Text("32").tag(32)
                }
                .pickerStyle(.segmented)

                Toggle("Haptic click at each step", isOn: $settings.hapticsEnabled)
                    .disabled(settings.detentCount == 0)
                Toggle("Show the dial on screen", isOn: $settings.hudEnabled)
            }

            Section {
                LabeledContent("Output", value: dial.outputDeviceName)
                if !dial.isSupported {
                    Label("No multitouch trackpad found.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if !dial.canControlVolume {
                    Label("This output has no software volume control.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppsTab: View {
    @ObservedObject var settings: Settings
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The dial stays out of the way in these apps, which use two-finger "
                 + "rotation themselves.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $selection) {
                ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                    HStack(spacing: 8) {
                        Image(nsImage: Self.icon(for: bundleID))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(Self.displayName(for: bundleID))
                        Spacer()
                        Text(bundleID)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .tag(bundleID)
                }
            }
            .border(Color.primary.opacity(0.1))

            HStack {
                Button("Add App…") { addApp() }
                Button("Remove") {
                    if let selection {
                        settings.excludedBundleIDs.removeAll { $0 == selection }
                        self.selection = nil
                    }
                }
                .disabled(selection == nil)
                Spacer()
                Button("Restore Defaults") { settings.resetExclusionsToDefault() }
            }
        }
        .padding()
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            if !settings.excludedBundleIDs.contains(bundleID) {
                settings.excludedBundleIDs.append(bundleID)
            }
        }
    }

    private static func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private static func displayName(for bundleID: String) -> String {
        guard let url = appURL(for: bundleID) else {
            return bundleID.components(separatedBy: ".").last ?? bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private static func icon(for bundleID: String) -> NSImage {
        guard let url = appURL(for: bundleID) else {
            return NSImage(systemSymbolName: "questionmark.app.dashed",
                           accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
