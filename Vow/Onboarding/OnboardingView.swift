import SwiftUI

struct OnboardingView: View {
    @Environment(VowStore.self) private var store

    @State private var vow: String = ""
    @State private var crew: Crew = .nightShift
    @State private var stake: Stake = .two
    @FocusState private var vowFocused: Bool

    private var trimmedVow: String {
        vow.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canStart: Bool {
        !trimmedVow.isEmpty
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView(.vertical, showsIndicators: false) {
                content
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
            hero
            vowSection
            crewSection
            stakeSection
            startButton
            footnote
        }
        .padding(.horizontal, 20)
        .padding(.top, 36)
        .padding(.bottom, 40)
        .contentShape(Rectangle())
        .onTapGesture {
            vowFocused = false
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Vow · Prototype")
                .eyebrow()
            Text("Make a vow.\nKeep the streak alive.")
                .font(Theme.display(34, .heavy))
                .gradientText()
                .fixedSize(horizontal: false, vertical: true)
            Text("Pick one daily vow, choose a crew and set a stake. Hold the orb to check in each day. Misses fill the pot; keepers split it.")
                .font(Theme.display(15, .regular))
                .foregroundStyle(Color.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Vow

    private var vowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your daily vow")
                .eyebrow()
            vowField
        }
    }

    private var vowField: some View {
        TextField(
            "",
            text: $vow,
            prompt: Text("I will train for 30 minutes").foregroundStyle(Color.white.opacity(0.35))
        )
        .font(Theme.display(18, .semibold))
        .foregroundStyle(Color.white)
        .focused($vowFocused)
        .submitLabel(.done)
        .onSubmit {
            vowFocused = false
        }
        .textInputAutocapitalization(.sentences)
        .autocorrectionDisabled(false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16, radius: 18)
    }

    // MARK: Crew

    private var crewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Crew")
                .eyebrow()
            crewMenu
        }
    }

    private var crewMenu: some View {
        Menu {
            ForEach(Crew.allCases) { option in
                Button {
                    crew = option
                } label: {
                    Text(option.title)
                    Text(option.subtitle)
                }
            }
        } label: {
            crewMenuLabel
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .tint(Color.white)
    }

    private var crewMenuLabel: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(crew.title)
                    .font(Theme.display(18, .semibold))
                    .foregroundStyle(Color.white)
                Text(crew.subtitle)
                    .font(Theme.mono(12, .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .glassCard(padding: 16, radius: 18)
    }

    // MARK: Stake

    private var stakeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily stake")
                .eyebrow()
            HStack(spacing: 10) {
                ForEach(Stake.allCases) { option in
                    StakeChip(label: option.label, selected: option == stake) {
                        stake = option
                    }
                }
            }
        }
    }

    // MARK: Start

    private var startButton: some View {
        Button {
            vowFocused = false
            store.start(vow: trimmedVow, crew: crew, stake: stake)
        } label: {
            Text("Start the streak")
                .font(Theme.display(18, .bold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Capsule().fill(Theme.brand))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canStart)
        .opacity(canStart ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: canStart)
    }

    private var footnote: some View {
        Text("Prototype · no real money moves")
            .font(Theme.mono(11, .medium))
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(maxWidth: .infinity)
    }
}

private struct StakeChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    private var rimStyle: AnyShapeStyle {
        selected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.white.opacity(0.15))
    }

    private var fillColor: Color {
        selected ? Theme.purple.opacity(0.22) : Color.white.opacity(0.05)
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.mono(14, .semibold))
                .foregroundStyle(Color.white.opacity(selected ? 1.0 : 0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(fillColor))
                .overlay(Capsule().strokeBorder(rimStyle, lineWidth: selected ? 1.25 : 0.75))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: selected)
    }
}
