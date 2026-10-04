import UIKit
import UniformTypeIdentifiers

/// Share → Ink Frame. Copies the shared photos into the app group's inbox, one folder per
/// share (read by lib/data/shared_inbox.dart), then opens the app with inkframe://share.
/// If the app can't be opened from here, it asks the person to open it; the app picks the
/// photos up when it comes to the front.
class ShareViewController: UIViewController {
  /// Also in AppDelegate.swift and both targets' entitlements.
  static let group = "group.com.psmyles.inkframe"

  private let stack = UIStackView()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let message = UILabel()
  private var started = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    spinner.startAnimating()
    message.text = "Adding to Ink Frame…"
    message.font = .preferredFont(forTextStyle: .body)
    message.numberOfLines = 0
    message.textAlignment = .center
    stack.axis = .vertical
    stack.spacing = 16
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    [spinner, message].forEach(stack.addArrangedSubview)
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !started else { return }
    started = true
    Task { @MainActor in
      let saved = await save()
      if saved > 0, await openApp() {
        extensionContext?.completeRequest(returningItems: nil)
      } else {
        finish(saved > 0 ? "Open Ink Frame to finish adding the photos." : "Ink Frame couldn't read these photos.")
      }
    }
  }

  /// Copies the photos into a folder of their own, then moves it into the inbox whole, so
  /// the app never sees half a share. Returns how many photos were saved.
  private func save() async -> Int {
    let files = FileManager.default
    guard let container = files.containerURL(forSecurityApplicationGroupIdentifier: Self.group) else { return 0 }
    let share = String(format: "%013lld-", Int64(Date().timeIntervalSince1970 * 1000)) + UUID().uuidString.prefix(8)
    let incoming = container.appendingPathComponent("share-incoming/\(share)", isDirectory: true)
    let inbox = container.appendingPathComponent("share-inbox", isDirectory: true)
    do {
      try files.createDirectory(at: incoming, withIntermediateDirectories: true)
      try files.createDirectory(at: inbox, withIntermediateDirectories: true)
    } catch {
      return 0
    }
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
      .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
    var saved = 0
    for (i, provider) in providers.enumerated() {
      if await copy(provider, into: incoming, index: i) { saved += 1 }
    }
    if saved == 0 || (try? files.moveItem(at: incoming, to: inbox.appendingPathComponent(share))) == nil {
      try? files.removeItem(at: incoming)
      return 0
    }
    return saved
  }

  /// The photo's original file where there is one (HEIC, JPEG, PNG…), else the image itself.
  private func copy(_ provider: NSItemProvider, into folder: URL, index: Int) async -> Bool {
    let type = provider.registeredTypeIdentifiers.compactMap { UTType($0) }.first { $0.conforms(to: .image) } ?? .jpeg
    let prefix = String(format: "%03d-", index)
    let original: Bool = await withCheckedContinuation { done in
      _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
        // The file is only there until this returns.
        guard let url else { return done.resume(returning: false) }
        let to = folder.appendingPathComponent(prefix + url.lastPathComponent)
        done.resume(returning: (try? FileManager.default.copyItem(at: url, to: to)) != nil)
      }
    }
    if original { return true }
    return await withCheckedContinuation { done in
      provider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
        let value: Any? = item
        var data: Data?
        var ext = type.preferredFilenameExtension ?? "jpg"
        switch value {
        case let d as Data: data = d
        case let url as URL: data = try? Data(contentsOf: url)
        case let image as UIImage:
          data = image.jpegData(compressionQuality: 0.95)
          ext = "jpg"
        default: data = nil
        }
        guard let data else { return done.resume(returning: false) }
        let to = folder.appendingPathComponent("\(prefix)photo-\(index + 1).\(ext)")
        done.resume(returning: (try? data.write(to: to)) != nil)
      }
    }
  }

  /// An extension can't use UIApplication.shared or its open(_:), but the app object is up
  /// the responder chain, and open(_:options:completionHandler:) can be called through the
  /// Objective-C runtime.
  private func openApp() async -> Bool {
    guard let url = URL(string: "inkframe://share") else { return false }
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
    var responder: UIResponder? = self
    while let r = responder {
      if let app = r as? UIApplication, app.responds(to: selector) {
        let open = unsafeBitCast(app.method(for: selector), to: Open.self)
        return await withCheckedContinuation { done in
          open(app, selector, url as NSURL, [:], { done.resume(returning: $0) })
        }
      }
      responder = r.next
    }
    return false
  }

  private func finish(_ text: String) {
    spinner.stopAnimating()
    spinner.isHidden = true
    message.text = text
    stack.addArrangedSubview(UIButton(type: .system, primaryAction: UIAction(title: "Done") { [weak self] _ in
      self?.extensionContext?.completeRequest(returningItems: nil)
    }))
  }
}
