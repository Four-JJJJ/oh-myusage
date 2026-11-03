import AppKit
import OhMyUsageApplication
import SwiftUI

extension SettingsView {
    func reorderHandle() -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(settingsHintColor)
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
    }

    func providerReorderHandle(providerID: String) -> some View {
        Button(action: {}) {
            reorderHandle()
        }
        .buttonStyle(.plain)
        .help(viewModel.text(.dragToReorder))
        .accessibilityLabel(viewModel.text(.dragToReorder))
        .onDrag {
            beginProviderReorderDrag(providerID: providerID)
        }
    }

    func beginProviderReorderDrag(providerID: String) -> NSItemProvider {
        navigationState.draggingProviderID = providerID
        navigationState.reorderPreviewProviderIDs = enabledSidebarProviders.map(\.id)
        navigationState.dropTargetProviderID = providerID
        navigationState.dropTargetInsertAfter = false
        installProviderReorderMouseUpMonitors(providerID: providerID)
        return NSItemProvider(object: providerID as NSString)
    }

    func commitProviderReorder() -> Bool {
        defer { resetProviderReorderState() }
        guard let sourceProviderID = navigationState.draggingProviderID else { return false }

        let originalIDs = viewModel.config.providers.filter { $0.family == selectedFamily && $0.enabled }.map(\.id)
        let previewIDs = navigationState.reorderPreviewProviderIDs ?? originalIDs
        // Map visible rows back to the persisted family order.
        guard let sourceIndex = originalIDs.firstIndex(of: sourceProviderID),
              let destinationIndex = SettingsProviderReorderPresenter.destination(
                providerID: sourceProviderID,
                previewIDs: previewIDs,
                allEnabledIDs: originalIDs
              ) else {
            return false
        }

        guard sourceIndex != destinationIndex else { return true }

        moveEnabledProviders(from: IndexSet(integer: sourceIndex), to: destinationIndex)
        navigationState.selectedProviderID = sourceProviderID
        return true
    }

    func resetProviderReorderState() {
        navigationState.clearProviderReorderingState()
        removeProviderReorderMouseUpMonitors()
    }

    func installProviderReorderMouseUpMonitors(providerID: String) {
        removeProviderReorderMouseUpMonitors()
        providerReorderLocalMouseUpMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { event in
            DispatchQueue.main.async {
                if navigationState.draggingProviderID == providerID {
                    resetProviderReorderState()
                }
            }
            return event
        }
        providerReorderGlobalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { _ in
            DispatchQueue.main.async {
                if navigationState.draggingProviderID == providerID {
                    resetProviderReorderState()
                }
            }
        }
    }

    func removeProviderReorderMouseUpMonitors() {
        if let providerReorderLocalMouseUpMonitor {
            NSEvent.removeMonitor(providerReorderLocalMouseUpMonitor)
            self.providerReorderLocalMouseUpMonitor = nil
        }
        if let providerReorderGlobalMouseUpMonitor {
            NSEvent.removeMonitor(providerReorderGlobalMouseUpMonitor)
            self.providerReorderGlobalMouseUpMonitor = nil
        }
    }

    func moveEnabledProviders(from source: IndexSet, to destination: Int) {
        viewModel.reorderEnabledProviders(
            family: selectedFamily,
            fromOffsets: source,
            toOffset: destination
        )
    }

    struct ProviderRowDropDelegate: DropDelegate {
        let targetProviderID: String
        let enabledProviderIDs: [String]
        @Binding var draggingProviderID: String?
        @Binding var previewProviderIDs: [String]?
        @Binding var dropTargetProviderID: String?
        @Binding var dropTargetInsertAfter: Bool
        let onPerformDrop: () -> Bool
        var insertAfterThresholdY: CGFloat = 19

        func validateDrop(info: DropInfo) -> Bool {
            draggingProviderID.map { enabledProviderIDs.contains($0) } ?? false
        }

        func dropEntered(info: DropInfo) {
            updatePreview(with: info)
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            updatePreview(with: info)
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            if dropTargetProviderID == targetProviderID {
                dropTargetProviderID = nil
            }
        }

        func performDrop(info: DropInfo) -> Bool {
            guard validateDrop(info: info) else { return false }
            updatePreview(with: info)
            return onPerformDrop()
        }

        private func updatePreview(with info: DropInfo) {
            guard let draggingProviderID, enabledProviderIDs.contains(draggingProviderID) else { return }
            guard draggingProviderID != targetProviderID else {
                dropTargetProviderID = nil
                return
            }

            let insertAfter = info.location.y > insertAfterThresholdY
            dropTargetProviderID = targetProviderID
            dropTargetInsertAfter = insertAfter

            previewProviderIDs = ProviderSidebarReorderPolicy.preview(
                ids: previewProviderIDs ?? enabledProviderIDs,
                draggingID: draggingProviderID,
                targetID: targetProviderID,
                insertAfter: insertAfter
            )
        }


    }
}
