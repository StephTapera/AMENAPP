// PlanVisitView.swift — AMEN IntegrationOS
// Liquid Glass plan-a-visit form combining transport and calendar actions.

import SwiftUI
import MapKit

struct PlanVisitView: View {
    let churchName: String
    let mapItem: MKMapItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var visitDate = Date().addingTimeInterval(86400)
    @State private var notes = ""
    @State private var addedToCalendar = false
    @State private var isWorking = false
    @State private var showTransport = false
    @State private var expectExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // MARK: What to Expect
                    GlassSection {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                expectExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Label("What to Expect", systemImage: "sparkles")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: expectExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        if expectExpanded {
                            VStack(alignment: .leading, spacing: 10) {
                                ExpectRow(icon: "door.left.hand.open", text: "Arrive 10–15 minutes early to find parking and get settled.")
                                ExpectRow(icon: "tshirt", text: "Dress is casual to smart-casual — come as you are.")
                                ExpectRow(icon: "person.2.wave.2", text: "A greeter will welcome you and help you find your way.")
                                ExpectRow(icon: "music.note", text: "Services typically include worship music, prayer, and a message.")
                            }
                            .padding(.top, 6)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    // MARK: Service Info
                    GlassSection {
                        Label("Service Info", systemImage: "clock")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        HStack(spacing: 8) {
                            ServiceTimePill(time: "9:00 AM")
                            ServiceTimePill(time: "11:00 AM")
                        }
                        .padding(.top, 4)
                    }

                    // MARK: Accessibility
                    GlassSection {
                        Label("Accessibility", systemImage: "figure.roll")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        VStack(spacing: 6) {
                            AccessibilityRow(icon: "figure.roll", label: "Wheelchair accessible entrance")
                            AccessibilityRow(icon: "car.2", label: "Parking lot available on-site")
                            AccessibilityRow(icon: "ear", label: "Hearing loop in main sanctuary")
                        }
                        .padding(.top, 4)
                    }

                    // MARK: Visit Date
                    GlassSection {
                        Label("Visit Date", systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        DatePicker(
                            "",
                            selection: $visitDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .padding(.top, 2)
                    }

                    // MARK: Notes
                    GlassSection {
                        Label("Notes", systemImage: "note.text")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        TextEditor(text: $notes)
                            .frame(minHeight: 80, maxHeight: 140)
                            .font(.subheadline)
                            .scrollContentBackground(.hidden)
                            .background(.clear)
                            .overlay(alignment: .topLeading) {
                                if notes.isEmpty {
                                    Text("Write a note about your visit…")
                                        .font(.subheadline)
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                            .padding(.top, 4)
                    }

                    // MARK: Actions row
                    HStack(spacing: 10) {
                        // Add to Calendar
                        Button {
                            Task { await addToCalendar() }
                        } label: {
                            HStack(spacing: 6) {
                                if isWorking {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: addedToCalendar ? "checkmark.circle.fill" : "calendar.badge.plus")
                                        .foregroundStyle(addedToCalendar ? .green : .primary)
                                }
                                Text(addedToCalendar ? "Added" : "Add to Calendar")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75)
                                    )
                            )
                            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                        .disabled(addedToCalendar || isWorking)

                        // Get Directions
                        Button {
                            showTransport = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.turn.up.right.circle")
                                Text("Get Directions")
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75)
                                    )
                            )
                            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)

                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(churchName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showTransport) {
                VisitPlanningView(destination: mapItem, churchName: churchName)
            }
        }
    }

    // MARK: - Helpers

    private func addToCalendar() async {
        isWorking = true
        defer { isWorking = false }
        let calService = AmenCalendarService.shared
        do {
            try await calService.addEvent(
                title: "Visit \(churchName)",
                startDate: visitDate,
                endDate: visitDate.addingTimeInterval(5400),
                notes: notes
            )
            addedToCalendar = true
        } catch {
            // Calendar permission may not be granted yet — surface gracefully.
        }
    }

    private func openInMaps() {
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
        ])
    }
}

// MARK: - Supporting Views

private struct GlassSection<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct ExpectRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ServiceTimePill: View {
    let time: String

    var body: some View {
        Text(time)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(.tertiarySystemBackground), in: Capsule())
    }
}

private struct AccessibilityRow: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
