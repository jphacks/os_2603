import Foundation
import UserNotifications

// 忘れかけた頃の復習通知。
// - 付箋作成時（reviewEnabled=true）に1日後の通知を登録。
// - 復習後に間隔を更新してスケジュールし直す（SM-2簡易版）。
// - 「覚えた」でキャンセル。
// - iOS の上限64件を超えた場合は古い分が自動で破棄される。

enum NotificationScheduler {

    // MARK: - 許可リクエスト

    static func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    // MARK: - 初回登録（付箋作成時）

    static func scheduleInitial(for sticky: Sticky) {
        guard sticky.reviewEnabled else { return }
        sticky.reviewInterval = 1
        sticky.nextReviewDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)
        schedule(sticky: sticky)
    }

    // MARK: - 復習後の間隔更新

    /// 「次へ」= succeeded false（短縮）、「覚えた」= succeeded true（延長）
    static func advanceInterval(for sticky: Sticky, succeeded: Bool) {
        cancel(stickyID: sticky.id)
        let next = succeeded
            ? min(Int((Double(sticky.reviewInterval) * 2.5).rounded()), 30)
            : max(sticky.reviewInterval / 2, 1)
        sticky.reviewInterval = next
        sticky.nextReviewDate = Calendar.current.date(byAdding: .day, value: next, to: .now)
        schedule(sticky: sticky)
    }

    // MARK: - キャンセル（mastered 時）

    static func cancel(stickyID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [stickyID.uuidString])
    }

    // MARK: - 内部

    private static func schedule(sticky: Sticky) {
        guard let date = sticky.nextReviewDate, date > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "復習の時間です"
        content.body = "p.\(sticky.pageNumber)「\(sticky.heading)」を確認しましょう"
        content.sound = .default

        // 翌朝9時に通知（日付だけ合わせて時刻を9:00に固定）
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = 9; comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: sticky.id.uuidString,
            content: content,
            trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
