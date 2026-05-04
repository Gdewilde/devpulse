import Foundation

/// Hybrid local + cloud routing policy. Determines whether a given task
/// should be routed to a local model or a cloud API based on rules,
/// current local capacity, and per-request hints.
///
/// The CLI's `devpulse route` verb is the operator's interface to this.
/// Agents shell out, branch on the exit code, run.
enum RoutingPolicy {

    /// Coarse task classes the router knows about. Hints from the caller.
    enum TaskClass: String, CaseIterable {
        case autocomplete       // latency-critical, small model is fine
        case drafting           // high-volume, low-complexity
        case summarization      // ditto
        case routineCode = "routine-code"
        case codeReview = "code-review"
        case explain
        case complexReasoning = "complex-reasoning"
        case multimodal
        case agenticPlanning = "agentic-planning"
        case novelDomain = "novel-domain"
        case unknown

        /// Default routing decision for the task class, before considering
        /// per-request privacy/latency hints or current capacity.
        var defaultRoute: Decision {
            switch self {
            case .autocomplete, .drafting, .summarization,
                 .routineCode, .codeReview, .explain:
                return .local
            case .complexReasoning, .multimodal, .agenticPlanning, .novelDomain:
                return .cloud
            case .unknown:
                return .either
            }
        }
    }

    enum Decision: String {
        case local
        case cloud
        case either   // no strong default — caller can pick
    }

    /// Routing input. The caller supplies whatever it knows; missing hints
    /// fall back to defaults.
    struct Request {
        let taskClass: TaskClass
        let modelSizeMB: Int?      // local model size, if known
        let privacyOnly: Bool      // forces local
        let maxLatencyMs: Int?     // <200ms typically forces local
        let prefer: Preference?

        enum Preference: String {
            case cost      // route local if it fits
            case quality   // route cloud
            case latency   // route local
        }
    }

    struct Outcome {
        let decision: Decision
        let reason: String
        /// Exit code mapping: 0=local, 1=cloud, 2=either, 3=cant-route.
        var exitCode: Int32 {
            switch decision {
            case .local:  return 0
            case .cloud:  return 1
            case .either: return 2
            }
        }
    }

    /// Decide where to route a request. Pure function over inputs and a
    /// snapshot of current capacity (the AIMemoryBudget the caller passes in).
    static func decide(_ request: Request, budget: AIMemoryBudget?) -> Outcome {
        // 1. Privacy short-circuit — if the caller marked the request privacy-only,
        //    local is the only legal answer.
        if request.privacyOnly {
            // But check capacity. If local can't fit, this is a real failure
            // mode that the caller has to know about.
            if let budget, let size = request.modelSizeMB,
               size > budget.availableForAIMB + budget.reclaimableFromIdleMB {
                return Outcome(
                    decision: .either,
                    reason: "privacy-only but local capacity insufficient — caller should free memory or queue"
                )
            }
            return Outcome(decision: .local, reason: "privacy-only request")
        }

        // 2. Latency short-circuit — sub-200ms first-token typically requires
        //    local on Apple Silicon.
        if let maxLatency = request.maxLatencyMs, maxLatency < 200 {
            return Outcome(decision: .local, reason: "latency budget < 200ms — local first-token wins")
        }

        // 3. Apply preference if set.
        if let prefer = request.prefer {
            switch prefer {
            case .cost:    return Outcome(decision: .local, reason: "prefer=cost — local has zero marginal cost")
            case .quality: return Outcome(decision: .cloud, reason: "prefer=quality — frontier API beats local on hardest tasks")
            case .latency: return Outcome(decision: .local, reason: "prefer=latency — local first-token < cloud queue")
            }
        }

        // 4. Default route from task class.
        let defaultRoute = request.taskClass.defaultRoute

        // 5. If default is local, sanity-check capacity. If local would OOM,
        //    fall back to cloud.
        if defaultRoute == .local, let budget, let size = request.modelSizeMB {
            let prediction = budget.predictLoadImpact(modelSizeMB: size)
            switch prediction {
            case .willNotFit:
                return Outcome(decision: .cloud, reason: "task-class default=local but model won't fit — fallback to cloud")
            case .tight:
                return Outcome(decision: .local, reason: "task-class default=local — fits tight (consider --auto-clean)")
            case .fitsAfterUnload:
                return Outcome(decision: .local, reason: "task-class default=local — fits after unloading idle (use --auto-clean)")
            case .comfortable:
                return Outcome(decision: .local, reason: "task-class default=local — fits comfortably")
            }
        }

        return Outcome(decision: defaultRoute,
                       reason: "task-class default=\(defaultRoute.rawValue)")
    }
}
