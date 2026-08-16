import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var dial: VolumeDial
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        TabView {
            DialTab(dial: dial)
                .tabItem { Label("Dial", systemImage: "dial.medium") }
            AppsTab()
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            AboutTab(updateChecker: updateChecker)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 470, height: 560)
    }
}

// MARK: - Dial

private struct DialTab: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var dial: VolumeDial

    /// How far through a full sweep the current twist has got.
    private var twistProgress: Double {
        guard settings.degreesForFullSweep > 0 else { return 0 }
        return min(abs(dial.liveTwistDegrees) / settings.degreesForFullSweep, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            liveHeader
            Divider()
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
                        Label("No trackpad found.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else if !dial.canControlVolume {
                        Label("This output has no volume control.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Button("Reset to Defaults") { settings.resetAll() }
                }
            }
            .formStyle(.grouped)
        }
    }

    /// A live dial you can twist against while the sliders are in front of you,
    /// so sensitivity is something you feel rather than a number you guess at.
    private var liveHeader: some View {
        HStack(spacing: 20) {
            DialGauge(level: Double(dial.volumeLevel),
                      detents: settings.detentCount,
                      lineWidth: 7) {
                Image(systemName: speakerSymbolName(level: Double(dial.volumeLevel),
                                                    isMuted: dial.isMuted))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 6) {
                if dial.isEngaged {
                    Text("\(Int(abs(dial.liveTwistDegrees)))° of \(Int(settings.degreesForFullSweep))°")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    ProgressView(value: twistProgress)
                        .frame(width: 190)
                    Text("Keep going to reach full range.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Twist to test")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    ProgressView(value: 0)
                        .frame(width: 190)
                        .opacity(0.35)
                    Text("Try it now with the sliders in view, then tune the feel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

// MARK: - Apps

private struct AppsTab: View {
    @ObservedObject var settings = Settings.shared
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                            .frame(width: 17, height: 17)
                        Text(Self.displayName(for: bundleID))
                        if !Self.isInstalled(bundleID) {
                            Text("not installed")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .tag(bundleID)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )

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
        .padding(20)
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

    private static func isInstalled(_ bundleID: String) -> Bool {
        appURL(for: bundleID) != nil
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

// MARK: - About

private struct AboutTab: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var updateChecker: UpdateChecker
    @State private var opensAtLogin = LoginItem.isEnabled

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    private var updateStatus: String {
        if updateChecker.isChecking { return "Checking…" }
        switch updateChecker.lastOutcome {
        case .upToDate: return "You're up to date."
        case .noReleasesYet: return "No releases published yet."
        case .failed: return "Couldn't reach GitHub."
        case .updateAvailable, .none: return ""
        }
    }

    var body: some View {
        VStack(spacing: 15) {
            Spacer()

            DialGauge(level: 0.68, detents: 16, lineWidth: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 78, height: 78)

            VStack(spacing: 3) {
                Text("TwistPad")
                    .font(.system(size: 19, weight: .semibold))
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let newVersion = updateChecker.availableVersion {
                VStack(spacing: 7) {
                    Label("Version \(newVersion) is available",
                          systemImage: "arrow.down.circle.fill")
                        .font(.callout.weight(.medium))
                    Button("Get Update") {
                        NSWorkspace.shared.open(UpdateChecker.releasesPage)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
            } else {
                HStack(spacing: 8) {
                    Button("Check for Updates") { updateChecker.check() }
                        .disabled(updateChecker.isChecking)
                    Text(updateStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 22)
            }

            VStack(alignment: .leading, spacing: 7) {
                Toggle("Check for updates automatically", isOn: $settings.automaticUpdateChecks)
                Toggle("Open at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, newValue in
                        LoginItem.set(newValue)
                        opensAtLogin = LoginItem.isEnabled
                    }
                    .disabled(!LoginItem.isAvailable)
            }
            .toggleStyle(.switch)
            .frame(maxWidth: 300, alignment: .leading)

            HStack(spacing: 10) {
                Button("Contact Support") {
                    open("mailto:Support@traluco.com?subject=TwistPad")
                }
                Button("View on GitHub") {
                    open("https://github.com/Toxic880/TwistPad")
                }
            }

            Text("MIT licensed.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
