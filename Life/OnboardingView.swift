import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @State private var page = 0
    @State private var nameInput = ""
    @FocusState private var nameFocused: Bool

    private let pages = 3

    var body: some View {
        ZStack {
            AppTheme.pageBg.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    namePage.tag(1)
                    readyPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                // Page dots + button
                VStack(spacing: 24) {
                    HStack(spacing: 8) {
                        ForEach(0..<pages, id: \.self) { i in
                            Capsule()
                                .fill(i == page ? AppTheme.primary : Color(.systemFill))
                                .frame(width: i == page ? 20 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: page)
                        }
                    }

                    Button {
                        if page < pages - 1 {
                            if page == 1 && !nameInput.trimmingCharacters(in: .whitespaces).isEmpty {
                                appState.setName(nameInput.trimmingCharacters(in: .whitespaces))
                            }
                            withAnimation { page += 1 }
                        } else {
                            UserDefaults.standard.set(true, forKey: "onboarding_complete")
                            isPresented = false
                        }
                    } label: {
                        Text(page == pages - 1 ? "Get Started" : "Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.primary)
                            .cornerRadius(AppTheme.buttonRadius)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 72))
                .foregroundColor(AppTheme.primary)
                .padding(28)
                .background(AppTheme.primary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 32))

            VStack(spacing: 12) {
                Text("Welcome to Life")
                    .font(.largeTitle.bold())
                Text("Your all-in-one personal OS.\nTasks, habits, training, health, and money — in one place.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 2: Name

    private var namePage: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "person.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(AppTheme.primary)

            VStack(spacing: 12) {
                Text("What should we call you?")
                    .font(.title2.bold())
                Text("We'll use your name to personalise your daily greeting.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            TextField("Your name", text: $nameInput)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(AppTheme.chipRadius)
                .focused($nameFocused)
                .padding(.horizontal, 32)
                .submitLabel(.continue)
                .onSubmit {
                    appState.setName(nameInput.trimmingCharacters(in: .whitespaces))
                    withAnimation { page += 1 }
                }

            Spacer()
            Spacer()
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { nameFocused = true } }
    }

    // MARK: - Page 3: Ready

    private var readyPage: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundColor(AppTheme.primary)

            VStack(spacing: 12) {
                Text("You're all set!")
                    .font(.title2.bold())
                Text("Here's what's waiting for you:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                featureRow("checkmark.circle.fill", color: Color(hex: "#5E9BF0"), title: "Tasks", subtitle: "Stay on top of what matters")
                featureRow("chart.bar.fill", color: AppTheme.primary, title: "Habits", subtitle: "Build streaks, break patterns")
                featureRow("dumbbell.fill", color: Color(hex: "#FF9F0A"), title: "Train", subtitle: "Log workouts & track PRs")
                featureRow("figure.stand", color: Color(hex: "#BF5AF2"), title: "Body", subtitle: "Monitor weight & measurements")
                featureRow("dollarsign.circle.fill", color: Color(hex: "#FF375F"), title: "Money", subtitle: "Track bills & outgoings")
            }
            .padding(20)
            .background(AppTheme.cardBg)
            .cornerRadius(AppTheme.cardRadius)
            .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func featureRow(_ icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
