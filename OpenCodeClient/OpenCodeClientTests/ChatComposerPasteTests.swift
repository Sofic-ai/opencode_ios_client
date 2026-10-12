import Testing
import UIKit
@testable import OpenCodeClient

@Suite(.serialized)
@MainActor
struct ChatComposerPasteTests {
    @Test func imagePasteCreatesAttachmentsWithoutReplacingDraft() throws {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        pasteboard.image = makeImage()
        let view = IMEAwareTextView()
        view.imagePasteboard = pasteboard
        view.text = "existing draft"
        var attachments: [ComposerImageAttachment] = []
        view.onPasteImages = { images in
            attachments = images.compactMap { try? ComposerImageTranscoder.makeAttachment(from: $0) }
        }

        #expect(view.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))
        #expect(attachments.isEmpty)
        view.paste(nil)

        #expect(view.text == "existing draft")
        #expect(attachments.count == 1)
        let attachment = try #require(attachments.first)
        #expect(attachment.mime == "image/jpeg")
        #expect(attachment.dataURL.hasPrefix("data:image/jpeg;base64,"))
        #expect(UIImage(data: attachment.thumbnailData) != nil)
        #expect(attachment.byteSize <= ComposerImageTranscoder.maxByteSize)
    }

    @Test func pastePreservesAllClipboardImages() {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        pasteboard.images = [makeImage(), makeImage()]
        let view = IMEAwareTextView()
        view.imagePasteboard = pasteboard
        var receivedCount = 0
        view.onPasteImages = { receivedCount = $0.count }

        view.paste(nil)

        #expect(receivedCount == 2)
    }

    @Test func plainTextPasteKeepsUIKitSelectionBehavior() async throws {
        let pasteboard = UIPasteboard.general
        let originalItems = pasteboard.items
        defer { pasteboard.items = originalItems }
        pasteboard.string = "replacement"
        let view = IMEAwareTextView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(view)
        view.frame = window.bounds
        window.makeKeyAndVisible()
        defer {
            view.resignFirstResponder()
            window.isHidden = true
        }
        #expect(view.becomeFirstResponder())
        view.text = "before selected after"
        view.selectedRange = NSRange(location: 7, length: 8)
        var receivedImages = false
        view.onPasteImages = { _ in receivedImages = true }

        view.paste(nil)
        // UIKit loads clipboard text asynchronously through an item provider.
        for _ in 0..<50 where view.text != "before replacement after" {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(view.text == "before replacement after")
        #expect(!receivedImages)
    }

    @Test func imageAndDataInputsUseTheSameAttachmentEncoding() throws {
        let image = makeImage()
        let data = try #require(image.pngData())
        let pasted = try ComposerImageTranscoder.makeAttachment(from: image)
        let uploaded = try ComposerImageTranscoder.makeAttachment(from: data)

        #expect(pasted.dataURL == uploaded.dataURL)
        #expect(pasted.thumbnailData == uploaded.thumbnailData)
        #expect(pasted.byteSize == uploaded.byteSize)
    }

    private func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
    }
}
