import Foundation

// MARK: - CRM Data Models

struct CRMJobTask: Identifiable, Codable {
    let id: String
    let title: String
    var completed: Bool
    let dueDate: String?
    let jobRef: String
    let jobTitle: String
    let leadId: String

    var dueDateParsed: Date? {
        guard let d = dueDate else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.date(from: d)
    }
}

struct CRMGeneralTask: Identifiable, Codable {
    let id: String
    let title: String
    var completed: Bool
    let dueDate: String?
    let priority: String
    let category: String
    let notes: String?

    var dueDateParsed: Date? {
        guard let d = dueDate else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.date(from: d)
    }
}

// MARK: - Raw Supabase response types

private struct LeadRow: Decodable {
    let id: String
    let jobRef: String?
    let name: String?
    let tasks: [RawJobTask]?

    enum CodingKeys: String, CodingKey {
        case id, tasks, name
        case jobRef = "job_ref"
    }
}

private struct RawJobTask: Decodable {
    let id: String
    let title: String
    let completed: Bool
    let dueDate: String?
    let isTemplate: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, completed
        case dueDate = "dueDate"
        case isTemplate = "isTemplate"
    }
}

private struct RawGeneralTask: Decodable {
    let id: String
    let title: String
    let completed: Bool
    let dueDate: String?
    let priority: String?
    let category: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, title, completed, notes
        case dueDate = "due_date"
        case priority, category
    }
}

// MARK: - CRM Service

@Observable
final class CRMService {

    private let supabaseURL = "https://qzvdzzvkocmulcfujyea.supabase.co"
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF6dmR6enZrb2NtdWxjZnVqeWVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg4NzIxNjUsImV4cCI6MjA5NDQ0ODE2NX0.g42AvuElukfbpgbg9Y6XImnuHQ2Po5GEaVVGMz3Siu0"

    var jobTasks: [CRMJobTask] = []
    var generalTasks: [CRMGeneralTask] = []
    var isLoading = false
    var error: String? = nil

    private var headers: [String: String] {
        ["apikey": anonKey, "Authorization": "Bearer \(anonKey)", "Content-Type": "application/json"]
    }

    // MARK: - Fetch

    func fetchAll() async {
        await MainActor.run { isLoading = true; error = nil }
        async let jobs: Void = fetchJobTasks()
        async let general: Void = fetchGeneralTasks()
        _ = await (jobs, general)
        await MainActor.run { isLoading = false }
    }

    private func fetchJobTasks() async {
        // Use the RPC function built into the CRM for this exact purpose
        guard let url = URL(string: "\(supabaseURL)/rest/v1/rpc/get_incomplete_job_tasks") else { return }

        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
            req.httpBody = "{}".data(using: .utf8)
            let (data, resp) = try await URLSession.shared.data(for: req)
            print("[CRM] job tasks raw:", String(data: data, encoding: .utf8) ?? "nil")

            // If RPC fails, fall back to direct table query with no stage filter
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                await fetchJobTasksDirect()
                return
            }

            // RPC returns [{task_id, task_title, lead_id, job_ref, customer_name, due_date}]
            struct RPCRow: Decodable {
                let task_id: String
                let task_title: String
                let lead_id: String
                let job_ref: String?
                let customer_name: String?
                let due_date: String?
            }
            let rows = try JSONDecoder().decode([RPCRow].self, from: data)
            let tasks = rows.map { r in
                CRMJobTask(
                    id: "\(r.lead_id)_\(r.task_id)",
                    title: r.task_title,
                    completed: false,
                    dueDate: r.due_date,
                    jobRef: r.job_ref ?? "JOB",
                    jobTitle: r.customer_name ?? "Unknown Job",
                    leadId: r.lead_id
                )
            }
            await MainActor.run { self.jobTasks = tasks }
        } catch {
            print("[CRM] job tasks error:", error)
            await fetchJobTasksDirect()
        }
    }

    private func fetchJobTasksDirect() async {
        var components = URLComponents(string: "\(supabaseURL)/rest/v1/leads")!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,job_ref,name,tasks"),
            URLQueryItem(name: "tasks", value: "not.is.null")
        ]
        guard let url = components.url else { return }

        do {
            var req = URLRequest(url: url)
            headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
            let (data, _) = try await URLSession.shared.data(for: req)
            print("[CRM] job tasks direct raw:", String(data: data, encoding: .utf8) ?? "nil")
            let rows = try JSONDecoder().decode([LeadRow].self, from: data)
            let tasks = rows.flatMap { lead -> [CRMJobTask] in
                (lead.tasks ?? [])
                    .filter { !$0.completed }
                    .map { t in
                        CRMJobTask(
                            id: "\(lead.id)_\(t.id)",
                            title: t.title,
                            completed: t.completed,
                            dueDate: t.dueDate,
                            jobRef: lead.jobRef ?? "JOB",
                            jobTitle: lead.name ?? "Unknown Job",
                            leadId: lead.id
                        )
                    }
            }
            await MainActor.run { self.jobTasks = tasks }
        } catch {
            print("[CRM] job tasks direct error:", error)
            await MainActor.run { self.error = "Failed to load job tasks" }
        }
    }

    private func fetchGeneralTasks() async {
        var components = URLComponents(string: "\(supabaseURL)/rest/v1/general_tasks")!
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]
        guard let url = components.url else { return }
        do {
            var req = URLRequest(url: url)
            headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
            let (data, _) = try await URLSession.shared.data(for: req)
            print("[CRM] general tasks raw:", String(data: data, encoding: .utf8) ?? "nil")
            let rows = try JSONDecoder().decode([RawGeneralTask].self, from: data)
            let tasks = rows.map { r in
                CRMGeneralTask(
                    id: r.id,
                    title: r.title,
                    completed: r.completed,
                    dueDate: r.dueDate,
                    priority: r.priority ?? "low",
                    category: r.category ?? "general",
                    notes: r.notes
                )
            }
            await MainActor.run { self.generalTasks = tasks }
        } catch {
            print("[CRM] general tasks error:", error)
            await MainActor.run { self.error = "Failed to load general tasks" }
        }
    }

    // MARK: - Complete Job Task

    func completeJobTask(_ task: CRMJobTask) async {
        // Update local immediately
        if let i = jobTasks.firstIndex(where: { $0.id == task.id }) {
            jobTasks[i].completed = true
        }

        // Fetch current tasks array for this lead, patch the specific task, write back
        guard let url = URL(string: "\(supabaseURL)/rest/v1/leads?id=eq.\(task.leadId)&select=tasks") else { return }
        do {
            var req = URLRequest(url: url)
            headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
            let (data, _) = try await URLSession.shared.data(for: req)

            // Parse as raw JSON to preserve unknown fields
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = arr.first,
                  var tasks = first["tasks"] as? [[String: Any]] else { return }

            // The real task id is the part after the leadId prefix
            let realTaskId = String(task.id.dropFirst(task.leadId.count + 1))
            for i in tasks.indices where tasks[i]["id"] as? String == realTaskId {
                tasks[i]["completed"] = true
                tasks[i]["completedDate"] = ISO8601DateFormatter().string(from: Date())
            }

            let patchBody = try JSONSerialization.data(withJSONObject: ["tasks": tasks])
            guard let patchURL = URL(string: "\(supabaseURL)/rest/v1/leads?id=eq.\(task.leadId)") else { return }
            var patchReq = URLRequest(url: patchURL)
            patchReq.httpMethod = "PATCH"
            headers.forEach { patchReq.setValue($1, forHTTPHeaderField: $0) }
            patchReq.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            patchReq.httpBody = patchBody
            _ = try await URLSession.shared.data(for: patchReq)
        } catch {}
    }

    // MARK: - Complete General Task

    func completeGeneralTask(_ task: CRMGeneralTask) async {
        if let i = generalTasks.firstIndex(where: { $0.id == task.id }) {
            generalTasks[i].completed = true
        }

        guard let url = URL(string: "\(supabaseURL)/rest/v1/general_tasks?id=eq.\(task.id)") else { return }
        do {
            let body = try JSONSerialization.data(withJSONObject: [
                "completed": true,
                "completed_date": ISO8601DateFormatter().string(from: Date())
            ])
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
            req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            req.httpBody = body
            _ = try await URLSession.shared.data(for: req)
        } catch {}
    }
}
