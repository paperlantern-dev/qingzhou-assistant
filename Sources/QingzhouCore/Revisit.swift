import Foundation

/// 主动智能 (off unless the user turns it on): customers who went quiet, to greet once.
public enum Revisit {
    /// Customers whose chat has been quiet for `minDays`–`maxDays`, who wrote to us at least once,
    /// were not greeted since they last wrote, never said “别发了”, and aren't waiting for a
    /// reservation. Most recently active first, at most `limit`.
    public static func candidates(in records: [CustomerRecord], now: Date = Date(), minDays: Int, maxDays: Int,
                                  limit: Int, skip: (CustomerRecord) -> Bool = { _ in false }) -> [CustomerRecord] {
        let picked = records.filter { r in
            guard r.optedOutAt == nil, !skip(r),
                  let theirs = r.messages.last(where: { !$0.fromMe })?.seenAt,
                  let last = r.messages.last?.seenAt else { return false }
            let days = now.timeIntervalSince(last) / 86400
            guard days >= Double(minDays), days <= Double(maxDays) else { return false }
            if let greeted = r.lastRevisitAt, greeted >= theirs { return false }
            return !r.reservations.contains { $0.status == .waiting }
        }
        return Array(picked.sorted { ($0.messages.last?.seenAt ?? .distantPast) > ($1.messages.last?.seenAt ?? .distantPast) }
            .prefix(max(0, limit)))
    }

    /// Whole days since the chat's last message.
    public static func quietDays(_ record: CustomerRecord, now: Date = Date()) -> Int {
        Int(now.timeIntervalSince(record.messages.last?.seenAt ?? record.lastSeen) / 86400)
    }
}
