import SwiftUI
import UserNotifications

@main
struct DueApp: App {
    @StateObject private var store = PaymentStore()
    var body: some Scene {
        WindowGroup { Dashboard().environmentObject(store).tint(.indigo) }
    }
}

struct Payment: Identifiable, Codable {
    var id = UUID()
    var name: String
    var amount: Decimal
    var day: Int
    var category: String
    var reminderDays: Int
    var paidMonths: Set<String> = []

    func date(in month: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: month)
        let start = calendar.date(from: components)!
        let days = calendar.range(of: .day, in: .month, for: start)!.count
        return calendar.date(byAdding: .day, value: min(day, days) - 1, to: start)!
    }
}

@MainActor
final class PaymentStore: ObservableObject {
    @Published var payments: [Payment] = []
    @Published var message: String?
    private let file = URL.documentsDirectory.appending(path: "payments.json")
    static func monthKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(c.year!)-\(c.month!)"
    }
    init() {
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                payments = try JSONDecoder().decode([Payment].self, from: Data(contentsOf: file))
            }
        } catch { message = "Your saved payments could not be opened. \(error.localizedDescription)" }
    }
    func save() {
        do { try JSONEncoder().encode(payments).write(to: file, options: .atomic) }
        catch { message = "Your changes could not be saved. \(error.localizedDescription)" }
        Task { await scheduleReminders() }
    }
    func toggle(_ payment: Payment, month: Date) {
        guard let index = payments.firstIndex(where: { $0.id == payment.id }) else { return }
        let key = Self.monthKey(month)
        if payments[index].paidMonths.contains(key) { payments[index].paidMonths.remove(key) }
        else { payments[index].paidMonths.insert(key) }
        save()
    }
    func enableReminders() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if allowed { await scheduleReminders() }
            else { message = "Reminders are off. You can enable notifications for Due in iPhone Settings." }
        } catch { message = error.localizedDescription }
    }
    func scheduleReminders() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        center.removeAllPendingNotificationRequests()
        var requests: [(Date, UNNotificationRequest)] = []
        // Schedule the nearest 60 alerts, below the system limit of 64.
        for offset in 0..<12 {
            let month = Calendar.current.date(byAdding: .month, value: offset, to: Date())!
            for payment in payments where !payment.paidMonths.contains(Self.monthKey(month)) {
                let due = payment.date(in: month)
                let reminder = Calendar.current.date(byAdding: .day, value: -payment.reminderDays, to: due)!
                let fire = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: reminder)!
                guard fire > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Upcoming payment: \(payment.name)"
                content.body = "\(payment.amount.formatted(.currency(code: currencyCode))) is due \(due.formatted(date: .abbreviated, time: .omitted))."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
                requests.append((fire, UNNotificationRequest(identifier: "\(payment.id)-\(Self.monthKey(month))", content: content, trigger: trigger)))
            }
        }
        for (_, request) in requests.sorted(by: { $0.0 < $1.0 }).prefix(60) {
            do { try await center.add(request) }
            catch { message = "A reminder could not be scheduled. \(error.localizedDescription)" }
        }
    }
}

var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

struct Dashboard: View {
    @EnvironmentObject private var store: PaymentStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var month = Date()
    @State private var adding = false
    @State private var editing: Payment?
    private var key: String { PaymentStore.monthKey(month) }
    private var total: Decimal { store.payments.reduce(0) { $0 + $1.amount } }
    private var remaining: Decimal { store.payments.filter { !$0.paidMonths.contains(key) }.reduce(0) { $0 + $1.amount } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
                        Spacer()
                        Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                        Spacer()
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LEFT TO PAY").font(.caption.weight(.semibold)).tracking(2)
                        Text(remaining, format: .currency(code: currencyCode)).font(.system(size: 40, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                        HStack {
                            Text("Monthly total \(total.formatted(.currency(code: currencyCode)))")
                            Spacer()
                            Text("\(store.payments.filter { $0.paidMonths.contains(key) }.count)/\(store.payments.count) paid")
                        }.font(.caption)
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white).background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 26))
                    HStack {
                        Text("Your payments").font(.title2.bold())
                        Spacer()
                        Button { Task { await store.enableReminders() } } label: { Image(systemName: "bell.badge") }.accessibilityLabel("Enable payment reminders")
                    }
                    if store.payments.isEmpty {
                        ContentUnavailableView { Label("A calmer month starts here", systemImage: "calendar.badge.clock") } description: { Text("Add your rent, subscriptions, bills, and other monthly payments.") } actions: { Button("Add your first payment") { adding = true }.buttonStyle(.borderedProminent) }
                    }
                    ForEach(store.payments.sorted { $0.day < $1.day }) { payment in
                        let paid = payment.paidMonths.contains(key)
                        HStack(spacing: 14) {
                            Button { store.toggle(payment, month: month) } label: {
                                Image(systemName: paid ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(paid ? .green : .secondary)
                            }.accessibilityLabel(paid ? "Mark \(payment.name) unpaid" : "Mark \(payment.name) paid")
                            Button { editing = payment } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(payment.name).font(.headline).foregroundStyle(.primary)
                                        Text("\(payment.category) · \(payment.date(in: month).formatted(.dateTime.month(.abbreviated).day()))").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 5) {
                                        Text(payment.amount, format: .currency(code: currencyCode)).fontWeight(.semibold).foregroundStyle(.primary)
                                        Text(status(payment)).font(.caption).foregroundStyle(paid ? .green : .secondary)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }
                    Text("Reminders arrive at 9 AM. Open Due regularly to refresh upcoming alerts. All amounts use \(currencyCode).")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }.background(Color(.systemGroupedBackground))
                .navigationTitle("Due")
                .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add payment") }
                .sheet(isPresented: $adding) { PaymentEditor(payment: nil) }
                .sheet(item: $editing) { PaymentEditor(payment: $0) }
                .alert("Payment update", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("OK") { store.message = nil } } message: { Text(store.message ?? "") }
                .task { await store.scheduleReminders() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.scheduleReminders() } } }
        }
    }
    private func shift(_ value: Int) { month = Calendar.current.date(byAdding: .month, value: value, to: month)! }
    private func status(_ payment: Payment) -> String {
        if payment.paidMonths.contains(key) { return "Paid" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: payment.date(in: month)).day ?? 0
        if days < 0 { return "Overdue" }
        if days == 0 { return "Due today" }
        return "In \(days) days"
    }
}

struct PaymentEditor: View {
    @EnvironmentObject private var store: PaymentStore
    @Environment(\.dismiss) private var dismiss
    let payment: Payment?
    @State private var name = ""
    @State private var amount = ""
    @State private var day = 1
    @State private var category = "Bills"
    @State private var reminder = 2
    @State private var deleting = false
    private var parsedAmount: Decimal? { Decimal(string: amount, locale: .current) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Internet", text: $name)
                    TextField("Amount (\(currencyCode))", text: $amount).keyboardType(.decimalPad)
                    Picker("Category", selection: $category) { ForEach(["Bills", "Housing", "Subscriptions", "Credit cards", "Insurance", "Other"], id: \.self) { Text($0) } }
                    Picker("Due day", selection: $day) { ForEach(1...31, id: \.self) { Text("\($0)") } }
                } header: { Text("Monthly payment") } footer: { Text("Repeats every month. For shorter months, the payment falls on the last day.") }
                Section("Reminder") {
                    Picker("Remind me", selection: $reminder) {
                        Text("On the due date").tag(0)
                        ForEach([1, 2, 3, 7], id: \.self) { Text("\($0) days before").tag($0) }
                    }
                    Button("Enable notifications") { Task { await store.enableReminders() } }
                }
                if payment != nil { Section { Button("Delete payment", role: .destructive) { deleting = true } } }
            }.navigationTitle(payment == nil ? "New payment" : "Edit payment")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { commit() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (parsedAmount ?? 0) <= 0) }
                }
                .confirmationDialog("Delete this recurring payment?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete payment", role: .destructive) { store.payments.removeAll { $0.id == payment?.id }; store.save(); dismiss() }
                }
                .onAppear {
                    if let payment { name = payment.name; amount = payment.amount.formatted(.number.grouping(.never)); day = payment.day; category = payment.category; reminder = payment.reminderDays }
                }
        }
    }
    private func commit() {
        guard let value = parsedAmount, value > 0 else { return }
        var updated = payment ?? Payment(name: "", amount: 0, day: 1, category: "Bills", reminderDays: 2)
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.amount = value; updated.day = day; updated.category = category; updated.reminderDays = reminder
        if let index = store.payments.firstIndex(where: { $0.id == updated.id }) { store.payments[index] = updated }
        else { store.payments.append(updated) }
        store.save(); dismiss()
    }
}
