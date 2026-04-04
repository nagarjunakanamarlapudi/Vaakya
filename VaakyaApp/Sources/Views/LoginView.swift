import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        @Bindable var auth = auth

        ZStack {
            Color.bgApp.ignoresSafeArea()

            VStack(spacing: 40) {
                // Logo area
                VStack(spacing: DesignTokens.Spacing.space3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                            .fill(Color.accent.opacity(0.12))
                            .frame(width: 72, height: 72)

                        Text("V")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accent)
                    }

                    Text("Vaakya")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.textPrimary)

                    Text("Meeting intelligence, organized")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondary)
                }

                // Sign-in buttons
                VStack(spacing: DesignTokens.Spacing.space4) {
                    // Sign In with Apple (native)
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { _ in
                        // Handled by ASAuthorizationControllerDelegate in AuthViewModel
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)
                    .cornerRadius(DesignTokens.Radius.md)
                    .onTapGesture {
                        auth.signInWithApple()
                    }

                    // Google Sign-In button
                    Button(action: {
                        Task {
                            await auth.signInWithGoogle()
                        }
                    }) {
                        HStack(spacing: DesignTokens.Spacing.space3) {
                            // Google "G" logo placeholder
                            ZStack {
                                Circle()
                                    .fill(Color.bgApp)
                                    .frame(width: 20, height: 20)
                                Text("G")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.red, .yellow, .green, .blue],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }

                            Text("Sign in with Google")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .fill(Color.bgApp)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    if auth.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(Color.accent)
                            .padding(.top, DesignTokens.Spacing.space1)
                    }

                    if let error = auth.errorMessage {
                        Text(error)
                            .font(DesignTokens.Typography.label)
                            .foregroundStyle(Color.blockRed)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: 280)
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 400)
        #endif
    }
}
