import SwiftUI

struct RecordGroupRow: View {
    let group: RecordGroup
    var showsDate: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(group.direction == .expense ? AppTheme.expense.opacity(0.12) : AppTheme.income.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: group.direction == .expense ? "arrow.up.right" : "arrow.down.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(group.direction == .expense ? AppTheme.expense : AppTheme.income)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(group.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if group.isSplit {
                        Text("拆分")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accentSoft)
                            .clipShape(Capsule())
                    }
                    if group.records.contains(where: { $0.pending }) {
                        Circle().fill(Color.orange).frame(width: 5, height: 5)
                    }
                }
                HStack(spacing: 5) {
                    if showsDate { Text(shortDate(group.date)) }
                    if !group.subtitle.isEmpty {
                        Text("· \(group.subtitle)")
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Text("\(group.direction.sign)\(money(group.amountCents))")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(group.direction == .expense ? AppTheme.expense : AppTheme.income)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct RecordRow: View {
    let record: LedgerRecord
    var showsDate: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(record.direction == .expense ? AppTheme.expense.opacity(0.12) : AppTheme.income.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: record.direction == .expense ? "arrow.up.right" : "arrow.down.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(record.direction == .expense ? AppTheme.expense : AppTheme.income)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.category.isEmpty ? "未分类" : record.category)
                        .font(.system(size: 15, weight: .semibold))
                    if record.pending {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                    }
                }
                HStack(spacing: 5) {
                    if showsDate {
                        Text(shortDate(record.date))
                    }
                    if !record.note.isEmpty {
                        Text("· \(record.note)")
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Text("\(record.direction.sign)\(money(record.amountCents))")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(record.direction == .expense ? AppTheme.expense : AppTheme.income)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct BalanceHero: View {
    let book: LedgerBook?
    let balanceCents: Int
    let incomeCents: Int
    let expenseCents: Int
    let monthTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(book?.name ?? "我的账本")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                    Text("当前余额")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                if let book {
                    Circle()
                        .fill(Color(hex: book.colorHex))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
                }
            }

            Text(money(balanceCents))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .monospacedDigit()

            HStack(spacing: 0) {
                metric(title: "\(monthTitle)收入", value: incomeCents, color: Color(red: 0.55, green: 0.94, blue: 0.76))
                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 1, height: 34)
                    .padding(.horizontal, 16)
                metric(title: "\(monthTitle)支出", value: expenseCents, color: Color(red: 1.0, green: 0.68, blue: 0.64))
            }
        }
        .padding(22)
        .background(
            ZStack {
                LinearGradient(colors: [AppTheme.heroTop, AppTheme.heroBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 170, height: 170)
                    .offset(x: 120, y: -70)
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 110, height: 110)
                    .offset(x: -140, y: 90)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
    }

    private func metric(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            Text(money(value))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

struct SectionTitle: View {
    let title: String
    var action: String?
    var onAction: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Spacer()
            if let action, let onAction {
                Button(action: onAction) {
                    Text(action)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }
}

struct SyncBadge: View {
    let isLoggedIn: Bool
    let isSyncing: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : (isLoggedIn ? "checkmark.icloud" : "icloud.slash"))
                .font(.system(size: 12, weight: .semibold))
            Text(isSyncing ? "同步中" : (isLoggedIn ? "已连接云端" : "本地模式"))
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(isLoggedIn ? AppTheme.accent : AppTheme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.accentSoft)
        .clipShape(Capsule())
    }
}
