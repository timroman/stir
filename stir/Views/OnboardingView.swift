import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var microphoneGranted = false
    @State private var showingDetails = false

    var body: some View {
        ZStack {
            SkyBackground(colors: NightSky.colors(NightSky.dusk))

            VStack(spacing: 40) {
                Spacer()

                // Wordmark
                VStack(spacing: 10) {
                    Text("stir")
                        .font(.system(size: 52, weight: .light))
                        .kerning(1.5)
                        .foregroundColor(NightSky.cream)
                    Text("wakes you when you do")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()

                // How the night works
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("one session, all night")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("white noise while you sleep, fading to silence before stir listens for you stirring — then a gentle wake, no later than your \"up by\" time.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                )

                Button(action: { showingDetails = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                        Text("how it works")
                            .font(.subheadline)
                    }
                    .foregroundColor(.white.opacity(0.7))
                }

                PermissionCard(
                    icon: "mic.fill",
                    title: "microphone",
                    description: "required to detect noise and wake you up",
                    isGranted: microphoneGranted,
                    isActive: !microphoneGranted
                ) {
                    requestMicrophonePermission()
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Continue button
            if microphoneGranted {
                Button(action: {
                    appState.completeOnboarding()
                }) {
                    Text("get started")
                        .font(.title2.bold())
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.white)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 40)
            } else {
                Text("grant permissions to continue")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Spacer()
                .frame(height: 40)
            }
        }
        .onAppear {
            checkExistingPermissions()
        }
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                TechnicalDetailsView()
            }
            .presentationDragIndicator(.visible)
        }
    }

    private func checkExistingPermissions() {
        // Check microphone
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            microphoneGranted = true
        default:
            break
        }
    }

    private func requestMicrophonePermission() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                microphoneGranted = granted
            }
        }
    }
}

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let isActive: Bool
    let onRequest: () -> Void

    var body: some View {
        Button(action: {
            if !isGranted && isActive {
                onRequest()
            }
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isGranted ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                        .frame(width: 50, height: 50)
                    Image(systemName: isGranted ? "checkmark" : icon)
                        .font(.title2)
                        .foregroundColor(isGranted ? .green : .white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                if !isGranted && isActive {
                    Text("allow")
                        .font(.subheadline.bold())
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .cornerRadius(20)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(isActive && !isGranted ? 0.1 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isActive && !isGranted ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .disabled(isGranted || !isActive)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
