import UIKit
import WebKit

class GutenbergWebViewController: UIViewController, WebKitAuthenticatable {
    let authenticator: RequestAuthenticator?
    var onSave: ((String) -> Void)?

    private let url: URL
    private let blockHTML: String
    private let jsInjection = GutenbergWebJavascriptInjection()

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = jsInjection.userContent(messageHandler: self, blockHTML: blockHTML)
        return WKWebView(frame: .zero, configuration: configuration)
    }()

    init?(with post: AbstractPost, blockHTML: String) {
        authenticator = RequestAuthenticator(blog: post.blog)
        self.blockHTML = blockHTML

        guard
            let siteURL = post.blog.homeURL,
            // Use wp-admin URL since Calypso URL won't work retriving the block content.
            let editorURL = URL(string: "\(siteURL)/wp-admin/post-new.php")
        else {
            return nil
        }

        url = editorURL

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.navigationDelegate = self;
        addNavigationBarElements()
        loadWebView()
    }

    private func loadWebView() {
        authenticatedRequest(for: url, on: webView) { [weak self] (request) in
            self?.webView.load(request)
        }
    }

    @objc func onSaveButtonPressed() {
        evaluateJavascript(jsInjection.getHTMLPostContentScript)
    }

    @objc func onCloseButtonPressed() {
        dismiss()
    }

    private func addNavigationBarElements() {
        let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(onSaveButtonPressed))
        let cancelButton = WPStyleGuide.buttonForBar(with: UIImage.gridicon(.cross), target: self, selector: #selector(onCloseButtonPressed))

        navigationItem.rightBarButtonItem = saveButton
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: cancelButton)
        title = NSLocalizedString("Edit on Web", comment: "Title of Gutenberg WEB editor running on a Web View")
    }

    private func evaluateJavascript(_ script: String) {
        webView.evaluateJavaScript(script) { (response, error) in
            if let response = response {
                print(response)
            }
            if let error = error {
                print(error)
            }
        }
    }

    private func save(_ newContent: String) {
        onSave?(newContent)
        dismiss()
    }

    private func dismiss() {
        cleanUpWebView()
        presentingViewController?.dismiss(animated: true)
    }

    private func cleanUpWebView() {
        webView.configuration.userContentController.removeAllUserScripts()
        GutenbergWebJavascriptInjection.JSMessage.allCases.forEach {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: $0.rawValue)
        }
    }
}

extension GutenbergWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        evaluateJavascript(jsInjection.insertCSSScript)
    }
}

extension GutenbergWebViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            let messageType = GutenbergWebJavascriptInjection.JSMessage(rawValue: message.name),
            let body = message.body as? String
        else {
            return
        }

        handle(messageType, body: body)
    }

    private func handle(_ message: GutenbergWebJavascriptInjection.JSMessage, body: String) {
        switch message {
        case .log:
            print("---> JS: " + body)
        case .htmlPostContent:
            save(body)
        }
    }
}
