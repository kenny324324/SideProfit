//
//  TransactionTypePickerSheet.swift
//  DevCal
//
//  Short sheet that asks the user to pick 支出 or 收入 before opening
//  AddTransactionView. Two capsule buttons filled with the type's tint color
//  (brick red / sage green) with fixed-white labels.
//

import SwiftUI

struct TransactionTypePickerSheet: View {
    var onSelect: (TransactionType) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var measuredContentHeight: CGFloat = 160

    var body: some View {
        NavigationStack {
            HStack(spacing: 12) {
                typeButton(.expense)
                typeButton(.income)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .frame(maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newValue in
                measuredContentHeight = newValue
            }
            .navigationTitle("紀錄類型")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(measuredContentHeight + 56)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(false)
        .modifier(TypePickerSheetBackground())
    }

    private func typeButton(_ type: TransactionType) -> some View {
        Button {
            onSelect(type)
            dismiss()
        } label: {
            Text(type.displayName)
                .appFont(.title2, weight: .semibold)
                .foregroundStyle(Theme.onTint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(TypeButtonBackground(type: type))
    }
}

private struct TypePickerSheetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.presentationBackground(.clear)
        } else {
            content.presentationBackground(Theme.appBackground)
        }
    }
}

private struct TypeButtonBackground: ViewModifier {
    let type: TransactionType

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(type.tint), in: Capsule())
        } else {
            content.background(type.tint, in: Capsule())
        }
    }
}
