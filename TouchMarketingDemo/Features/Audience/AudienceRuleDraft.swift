import Foundation

struct AudienceConditionDraft: Identifiable, Equatable {
    var id = UUID().uuidString
    var field: AudienceField
    var operation: AudienceRuleOperator = .equals
    var text = ""
    var upper = ""
    var date = DemoClock.referenceDate
    var boolean = true

    init(field: AudienceField) {
        self.field = field
        text = field.options.first ?? ""
    }
    init(condition: AudienceRuleCondition) {
        id = condition.id; field = condition.field; operation = condition.operation
        switch condition.value {
        case .number(let n): text = String(n)
        case .range(let a, let b): text = String(a); upper = String(b)
        case .category(let s): text = s
        case .date(let d): date = d
        case .boolean(let b): boolean = b
        }
    }
    func condition() throws -> AudienceRuleCondition {
        let value: AudienceRuleValue
        switch field.type {
        case .number:
            guard let lower = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), lower.isFinite, lower >= 0 else { throw DemoValidationError(message: "\(field.name)：请输入有效的非负数字。") }
            if operation == .between {
                guard let upper = Double(upper.trimmingCharacters(in: .whitespacesAndNewlines)), upper.isFinite, upper >= lower else { throw DemoValidationError(message: "\(field.name)：区间上限不能小于下限。") }
                value = .range(lower, upper)
            } else { value = .number(lower) }
        case .category: value = .category(text)
        case .date: value = .date(DemoClock.calendar.startOfDay(for: date))
        case .boolean: value = .boolean(boolean)
        }
        return .init(id: id, field: field, operation: operation, value: value)
    }
}
