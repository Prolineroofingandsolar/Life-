import SwiftUI

// MARK: - More View

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(destination: BodyView()) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Body").font(.headline)
                                Text("Weight, measurements & lifts").font(.caption).foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "figure.stand")
                                .foregroundColor(AppTheme.primary)
                                .frame(width: 30)
                        }
                    }

                    NavigationLink(destination: MoneyView()) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Money").font(.headline)
                                Text("Bills & monthly outgoings").font(.caption).foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundColor(Color(hex: "#30d158"))
                                .frame(width: 30)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
