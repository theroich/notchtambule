//
//  OCRPromptView.swift
//  NotchTubeAudio
//
//  Created by NotchTubeAudio.
//

import AppKit
import Observation
import SwiftUI

/// Observable state machine for the OCR notch prompt.
@MainActor
@Observable
final class OCRPromptViewModel {
    enum State: Equatable {
        case loading
        case loaded(OCRResult)
        case empty
        case failed(String)
    }

    private(set) var state: State = .loading
    var selectedText: String = ""

    private let imagePayload: ImagePayload
    private let options: OCROptions
    private let ocrService: any OCRServicing
    private let context: FeatureActionContext
    private let onComplete: () -> Void
    private let onDismiss: () -> Void

    @ObservationIgnored private var recognitionTask: Task<Void, Never>?
    @ObservationIgnored private var isCancelled = false

    init(
        imagePayload: ImagePayload,
        options: OCROptions,
        ocrService: any OCRServicing,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.imagePayload = imagePayload
        self.options = options
        self.ocrService = ocrService
        self.context = context
        self.onComplete = onComplete
        self.onDismiss = onDismiss
    }

    var hasSelection: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start() async {
        guard recognitionTask == nil else { return }
        isCancelled = false
        state = .loading
        selectedText = ""

        let imageData = imagePayload.tiffOrPngData
        let currentOptions = options
        let service = ocrService

        let task = Task { @MainActor [weak self] in
            do {
                let result = try await service.recognizeText(in: imageData, options: currentOptions)
                guard !Task.isCancelled, let self, !self.isCancelled else { return }
                if result.isEmpty {
                    self.state = .empty
                } else {
                    self.state = .loaded(result)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self, !self.isCancelled else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
        recognitionTask = task
        await task.value
    }

    func cancelTask() {
        isCancelled = true
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    func copyAll() {
        guard case .loaded(let result) = state, !result.isEmpty else { return }
        context.writeToClipboard(.text(result.fullText))
        context.notifyUser(message: L10n.string("plugin.ocr.notify.copied"), icon: "doc.on.doc.fill")
        onComplete()
    }

    func copySelection() {
        guard hasSelection else { return }
        context.writeToClipboard(.text(selectedText))
        context.notifyUser(message: L10n.string("plugin.ocr.notify.copied"), icon: "doc.on.doc.fill")
        onComplete()
    }

    func dismiss() {
        cancelTask()
        onDismiss()
    }
}

/// Notch prompt view that runs local Vision OCR on a copied image and lets the user
/// inspect, select, and copy the recognized text.
struct OCRPromptView: View {
    @State private var viewModel: OCRPromptViewModel

    init(
        imagePayload: ImagePayload,
        options: OCROptions,
        ocrService: any OCRServicing,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self._viewModel = State(
            initialValue: OCRPromptViewModel(
                imagePayload: imagePayload,
                options: options,
                ocrService: ocrService,
                context: context,
                onComplete: onComplete,
                onDismiss: onDismiss
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            contentArea
                .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 168)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )

            footerControls
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .task {
            await viewModel.start()
        }
        .onDisappear {
            viewModel.cancelTask()
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.75))

                Text(L10n.string("plugin.ocr.prompt.loading"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)

        case .loaded(let result):
            SelectableOCRTextView(
                text: result.fullText,
                selectedText: Binding(
                    get: { viewModel.selectedText },
                    set: { viewModel.selectedText = $0 }
                )
            )
            .padding(2)

        case .empty:
            VStack(spacing: 6) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))

                Text(L10n.string("plugin.ocr.prompt.empty"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)

        case .failed(let message):
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(L10n.string("plugin.ocr.prompt.error"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)

                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        }
    }

    private var footerControls: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button {
                viewModel.dismiss()
            } label: {
                Text(L10n.string("plugin.ocr.prompt.close"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5.5)
                    .background(Capsule().fill(.white.opacity(0.10)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("plugin.ocr.prompt.close"))

            if case .loaded = viewModel.state {
                if viewModel.hasSelection {
                    Button {
                        viewModel.copySelection()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "selection.pin.in.out")
                                .font(.system(size: 10, weight: .semibold))
                            Text(L10n.string("plugin.ocr.prompt.copy_selection"))
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5.5)
                        .background(Capsule().fill(.white.opacity(0.18)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("plugin.ocr.prompt.copy_selection"))
                }

                Button {
                    viewModel.copyAll()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(L10n.string("plugin.ocr.prompt.copy_all"))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5.5)
                    .background(Capsule().fill(.white))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("plugin.ocr.prompt.copy_all"))
            }
        }
    }
}

// MARK: - Selectable Scrollable NSTextView Wrapper

private struct SelectableOCRTextView: NSViewRepresentable {
    let text: String
    @Binding var selectedText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.font = NSFont.systemFont(ofSize: 11.5)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var selectedText: String

        init(selectedText: Binding<String>) {
            self._selectedText = selectedText
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let nsString = textView.string as NSString
            let extracted: String
            if range.length > 0, NSMaxRange(range) <= nsString.length {
                extracted = nsString.substring(with: range)
            } else {
                extracted = ""
            }
            if selectedText != extracted {
                Task { @MainActor [weak self] in
                    self?.selectedText = extracted
                }
            }
        }
    }
}
