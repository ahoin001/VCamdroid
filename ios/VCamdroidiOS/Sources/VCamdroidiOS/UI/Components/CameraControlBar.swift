import SwiftUI

/// Primary camera controls surfaced during streaming (exposure, WB, portrait bokeh).
public struct CameraControlBar: View {
    @ObservedObject var controller: StreamController

    @State private var portraitOn = false
    @State private var portraitStrength: Double = 50
    @State private var evBias: Double = 0
    @State private var wbTemp: Double = 5500
    @State private var manualExposure = false
    @State private var manualWB = false

    public init(controller: StreamController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("While streaming")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            portraitSection
            Divider().overlay(Theme.Color.divider)
            exposureSection
            Divider().overlay(Theme.Color.divider)
            whiteBalanceSection
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.Color.cardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var portraitSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Toggle(isOn: $portraitOn) {
                Label("Soft background blur", systemImage: "person.crop.circle")
                    .font(Theme.Font.caption)
            }
            .tint(Theme.Color.accent)
            .onChange(of: portraitOn) { on in
                controller.setPortraitMode(enabled: on, strength: Int(portraitStrength), promptVideoEffects: on)
            }

            if portraitOn {
                Text("Optional: Apple’s own Portrait effect opens in a sheet. This slider is a calm fallback when that’s off.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    StreamController.presentSystemVideoEffectsPicker()
                } label: {
                    Label("Apple Video Effects…", systemImage: "slider.horizontal.3")
                        .font(Theme.Font.caption)
                }
                .buttonStyle(.borderless)

                HStack {
                    Text("Blur strength")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                    Slider(value: $portraitStrength, in: 0...100, step: 1)
                        .tint(Theme.Color.accent)
                        .onChange(of: portraitStrength) { v in
                            controller.setPortraitMode(enabled: true, strength: Int(v), promptVideoEffects: false)
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var exposureSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack {
                Text("Brightness")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Picker("", selection: $manualExposure) {
                    Text("Auto").tag(false)
                    Text("Manual").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            HStack {
                Text("Light touch")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
                Slider(value: $evBias, in: -2...2, step: 0.1)
                    .onChange(of: evBias) { v in
                        controller.setExposureCompensation(Float(v))
                    }
            }

            if manualExposure {
                Text("Fine shutter & ISO live on your PC — keep both apps open.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var whiteBalanceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack {
                Text("Color warmth")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Picker("", selection: $manualWB) {
                    Text("Auto").tag(false)
                    Text("Manual").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            if manualWB {
                HStack {
                    Text("Warm ⟷ cool")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Slider(value: $wbTemp, in: 2500...10000, step: 100)
                        .onChange(of: wbTemp) { v in
                            controller.setWhiteBalance(temperatureK: Float(v), tint: 0)
                        }
                }
            }
        }
    }
}
