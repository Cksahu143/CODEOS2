import Foundation

public struct BatchRenameRule: Equatable {
    /// Literal text to find in each name (every occurrence). Empty means no find/replace.
    public var find: String = ""
    public var replaceWith: String = ""
    public var prefix: String = ""
    /// Added after the name and before the extension.
    public var suffix: String = ""
    /// When set, " 01", " 02", ... is added to each name, starting at this number.
    public var numberStart: Int? = nil
    public var numberWidth: Int = 2

    public init() {}
}

public struct BatchRenamePreview: Equatable {
    public let original: String
    public let proposed: String
    /// Why this name cannot be used, or nil when the rename is safe to apply.
    public let problem: String?
}

public enum BatchRename {
    /// Computes the new names for a batch. Nothing is renamed here.
    /// `existing` holds every name in the folder that is NOT part of this batch.
    public static func preview(names: [String], rule: BatchRenameRule, existing: Set<String> = []) -> [BatchRenamePreview] {
        let proposed: [String] = names.enumerated().map { pair in
            propose(pair.element, index: pair.offset, rule: rule)
        }
        var counts: [String: Int] = [:]
        for name in proposed {
            counts[name, default: 0] += 1
        }
        var previews: [BatchRenamePreview] = []
        for index in 0..<names.count {
            let original = names[index]
            let new = proposed[index]
            var problem: String? = nil
            if !FileOperationPlanner.isSafeComponent(new) {
                problem = "not a valid name"
            } else if (counts[new] ?? 0) > 1 {
                problem = "two items would get this name"
            } else if new != original && existing.contains(new) {
                problem = "a file with this name already exists"
            }
            previews.append(BatchRenamePreview(original: original, proposed: new, problem: problem))
        }
        return previews
    }

    static func propose(_ name: String, index: Int, rule: BatchRenameRule) -> String {
        let ns = name as NSString
        let ext = ns.pathExtension
        var base = ext.isEmpty ? name : ns.deletingPathExtension
        if !rule.find.isEmpty {
            base = base.replacingOccurrences(of: rule.find, with: rule.replaceWith)
        }
        base = rule.prefix + base
        if let start = rule.numberStart {
            let raw = String(start + index)
            let padding = String(repeating: "0", count: max(0, rule.numberWidth - raw.count))
            base += " " + padding + raw
        }
        base += rule.suffix
        return ext.isEmpty ? base : base + "." + ext
    }
}
