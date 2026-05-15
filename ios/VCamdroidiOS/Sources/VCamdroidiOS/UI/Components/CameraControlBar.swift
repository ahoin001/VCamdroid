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
        VStack(spacing: Theme.Spacing.sm) {
            portraitSection
            exposureSection
            whiteBalanceSection
        }
        .padding(Theme.Spacing.md)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var portraitSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Toggle(isOn: $portraitOn) {
                Label("Portrait Mode", systemImage: "person.crop.circle")
                    .font(Theme.Font.caption)
            }
            .tint(Theme.Color.accent)
            .onChange(of: portraitOn) { on in
                controller.setPortraitMode(enabled: on, strength: Int(portraitStrength), promptVideoEffects: on)
            }

            if portraitOn {
                Text("For Apple’s Portrait blur, enable Portrait in Video Effects (a sheet opens when you turn this on). The slider adjusts the on-device fallback while system Portrait is off.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    StreamController.presentSystemVideoEffectsPicker()
                } label: {
                    Label("Video Effects…", systemImage: "slider.horizontal.3")
                        .font(Theme.Font.caption)
                }
                .buttonStyle(.borderless)

                HStack {
                    Text("Fallback strength")
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
                Text("Exposure")
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
                Text("EV")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
                Slider(value: $evBias, in: -2...2, step: 0.1)
                    .onChange(of: evBias) { v in
                        controller.setExposureCompensation(Float(v))
                    }
            }

            if manualExposure {
                Text("Shutter / ISO are controlled from VCamdroid Desktop")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var whiteBalanceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack {
                Text("White balance")
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
                    Text("Temp")
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
