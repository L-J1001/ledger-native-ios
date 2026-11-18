import SwiftUI

/// 本地数据体检：不联网、不读隐私，只检查本机账目结构是否正常。
struct HealthView: View {
    @EnvironmentObject private var store: LedgerStore

    private var currentRecords: [LedgerRecord] {
        store.records(for: store.writeBookID)
    }

    private var emptyCategoryCount: Int {
        currentRecords.filter { $0.category.isEmpty || $0.category == "未分类" }.count
    }

    private var emptyMemberCount: Int {
        currentRecords.filter { $0.member.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var duplicateGroups: Int {
        let keyed = Dictionary(grouping: currentRecords) { record in
            "\(record.date)|\(record.direction.rawValue)|\(record.member)|\(record.amountCents)"
        }
        return keyed.values.filter { $0.count > 1 }.count
    }

    private var splitGroupCount: Int {
        Set(currentRecords.compactMap(\.splitGroup).filter { !$0.isEmpty }).count
    }

    var body: some View {
        List {
            Section("当前账本") {
                LabeledContent("账本", value: store.selectedBook?.name ?? "我的账本")
                LabeledContent("账目", value: "\(currentRecords.count) 条")
                LabeledContent("拆分账单", value: "\(splitGroupCount) 组")
                LabeledContent("待同步", value: "\(store.pendingCount) 条")
            }

            Section("结构检查") {
                checkRow("分类为空 / 未分类", count: emptyCategoryCount, hint: "建议补齐分类")
                checkRow("成员为空", count: emptyMemberCount, hint: "会被归到「我」")
                checkRow("疑似重复账目", count: duplicateGroups, hint: "只提示，不会自动删除")
                checkRow("回收站", count: store.trashRecords.count, hint: "可还原或彻底删除")
            }

            Section {
                Text("体检只在本机运行，不上传任何账目；发现疑似重复只提示，不改数据。")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .navigationTitle("数据体检")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func checkRow(_ title: String, count: Int, hint: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: count == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(count == 0 ? AppTheme.income : Color.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(count == 0 ? "正常" : "\(count) 处 · \(hint)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}
