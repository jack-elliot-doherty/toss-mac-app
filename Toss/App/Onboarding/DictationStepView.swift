import SwiftUI

struct DictationStepView: View {
    @State private var dictatedText = ""
    @FocusState private var isFocused: Bool
    @ObservedObject private var manager = OnboardingManager.shared

    var body: some View {
        VStack(spacing: 32) {
            // Headline
            VStack(spacing: 12) {
                Text("Try dictating")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                HStack(spacing: 4) {
                    Text("Hold")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.secondaryText)
                    KeyboardKey("fn")
                    Text(", speak, release to type")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }

            // Practice text area
            VStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    // Placeholder
                    if dictatedText.isEmpty {
                        Text("Your words will appear here...")
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.secondaryText.opacity(0.5))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                    }

                    TextEditor(text: $dictatedText)
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.primaryText)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                }
                .frame(height: 100)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    isFocused ? AppTheme.accent : AppTheme.subtleStroke, lineWidth: 1
                                )
                        )
                )

                if dictatedText.isEmpty {
                    Text("Try saying: \"Hello, this is a test\"")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                } else {
                    // Success message when they've dictated something
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Nice! Dictation is working")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                }
            }

            // Tip
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
                Text("This works in any text field, in any app on your Mac")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.yellow.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.yellow.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .onAppear {
            // Delay focus slightly to ensure view is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
        .onChange(of: dictatedText) { _, newValue in
            // Mark as tested once user has dictated something
            if !newValue.isEmpty && !manager.dictationTested {
                manager.dictationTested = true
            }
        }
    }
}

#Preview {
    ZStack {
        AppGlassBackground()
        DictationStepView()
            .frame(maxWidth: 520)
            .padding(40)
    }
    .frame(width: 700, height: 580)
}
