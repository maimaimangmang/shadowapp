import AppKit
import CodexMultiCore
import SwiftUI

typealias LauncherApplication = ManagedApplication

// Use the installed application's own icon, including after an application update.
struct ApplicationIcon: View {
    let applicationURL: URL?
    var size: CGFloat = 22
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: applicationURL) {
            icon = applicationURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
    }
}

struct ApplicationSidebar: View {
    @Binding var selection: LauncherApplication
    var installationURLs: [ManagedApplication: URL] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: ShadowAppBrand.image(size: 32))
                    .accessibilityHidden(true)
                Text("ShadowApp").font(.system(size: 14, weight: .semibold))
            }

            Text(Texts.t("应用", "APPLICATIONS"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 32).padding(.bottom, 10).padding(.leading, 10)
            ForEach(LauncherApplication.allCases) { application in
                Button {
                    selection = application
                } label: {
                    HStack(spacing: 11) {
                        ApplicationIcon(applicationURL: installationURLs[application])
                        Text(application.name).font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 11).padding(.vertical, 11)
                    .background(selection == application ? LauncherAppearance.card : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == application ? LauncherAppearance.border : .clear, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(application.name)
                .accessibilityAddTraits(selection == application ? .isSelected : [])
            }
            Spacer(minLength: 30)
            Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "DEV")  /  PREVIEW")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary).padding(.leading, 10)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14).padding(.top, 38).padding(.bottom, 20)
        .frame(width: 184)
        .background(LauncherAppearance.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(LauncherAppearance.border).frame(width: 1) }
    }
}
