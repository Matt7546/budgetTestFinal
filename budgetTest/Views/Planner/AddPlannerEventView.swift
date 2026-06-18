import SwiftUI
import SwiftData

struct AddPlannerEventView: View {

    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.dismiss)
    private var dismiss

    let editingEvent: PlannerEvent?

    @State private var name = ""
    @State private var amount = ""

    @State private var date = Date()

    @State private var type: PlannerEventType = .expense

    @State private var frequency: PlannerFrequency = .monthly

    private var canSave: Bool {

        !name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        &&
        Double(amount) != nil
        &&
        Double(amount) ?? 0 > 0
    }

    var body: some View {

        NavigationStack {

            Form {

                Section("Details") {

                    TextField(
                        "Name",
                        text: $name
                    )

                    TextField(
                        "Amount",
                        text: $amount
                    )
                    .keyboardType(.decimalPad)

                    Picker(
                        "Type",
                        selection: $type
                    ) {

                        ForEach(
                            PlannerEventType.allCases
                        ) { type in

                            Text(type.rawValue)
                                .tag(type)
                        }
                    }
                }

                Section("Schedule") {

                    DatePicker(
                        "Date",
                        selection: $date,
                        displayedComponents: .date
                    )

                    Picker(
                        "Frequency",
                        selection: $frequency
                    ) {

                        ForEach(
                            PlannerFrequency.allCases
                        ) { frequency in

                            Text(
                                frequency.rawValue
                            )
                            .tag(frequency)
                        }
                    }
                }

                if let editingEvent {

                    Section {

                        Button(
                            role: .destructive
                        ) {

                            modelContext.delete(
                                editingEvent
                            )

                            dismiss()

                        } label: {

                            Label(
                                "Delete Event",
                                systemImage: "trash"
                            )
                        }
                    }
                }
            }
            .navigationTitle(
                editingEvent == nil
                ? "New Event"
                : "Edit Event"
            )
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {

                guard let event = editingEvent else {
                    return
                }

                name = event.name
                amount = String(event.amount)
                date = event.date
                type = event.type
                frequency = event.frequency
            }
            .toolbar {

                ToolbarItem(
                    placement: .cancellationAction
                ) {

                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {

                    Button(
                        editingEvent == nil
                        ? "Save"
                        : "Update"
                    ) {

                        guard
                            let amountValue =
                                Double(amount)
                        else {
                            return
                        }

                        if let editingEvent {

                            editingEvent.name = name
                            editingEvent.amount = amountValue
                            editingEvent.date = date
                            editingEvent.frequency = frequency
                            editingEvent.type = type

                        } else {

                            let newEvent =
                                PlannerEvent(
                                    name: name,
                                    amount: amountValue,
                                    date: date,
                                    frequency: frequency,
                                    type: type
                                )

                            modelContext.insert(
                                newEvent
                            )
                        }

                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
