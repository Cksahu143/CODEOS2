import AppKit
import SwiftUI
import WebKit

/// Monaco is the editor engine inside VS Code. It runs in a web view, loaded from a pinned jsDelivr release.
/// The first load needs internet access.
struct MonacoEditor: NSViewRepresentable {
    let documentID: String
    let text: String
    let language: String
    let saveTick: Int
    let onDirty: (Bool) -> Void
    let onSave: (String) -> String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(ScriptProxy(context.coordinator), name: "codeos")
        configuration.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        webView.loadHTMLString(MonacoEditor.page, baseURL: URL(string: "https://codeos.local/"))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.documentID != documentID {
            coordinator.documentID = documentID
            coordinator.pendingText = text
            coordinator.pendingLanguage = language
            coordinator.push()
        }
        if coordinator.lastSaveTick != saveTick {
            coordinator.lastSaveTick = saveTick
            coordinator.run("codeosRequestSave()")
        }
    }

    static let page = #"""
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
      html, body, #container { height: 100%; margin: 0; background: #1e1e1e; overflow: hidden; }
    </style>
    </head>
    <body>
    <div id="container"></div>
    <script src="https://cdn.jsdelivr.net/npm/monaco-editor@0.52.0/min/vs/loader.js"></script>
    <script>
      var editor = null;
      var current = null;
      var lastSaved = "";

      function post(message) {
        window.webkit.messageHandlers.codeos.postMessage(message);
      }

      require.config({ paths: { vs: "https://cdn.jsdelivr.net/npm/monaco-editor@0.52.0/min/vs" } });
      require(["vs/editor/editor.main"], function () {
        editor = monaco.editor.create(document.getElementById("container"), {
          value: "",
          language: "plaintext",
          theme: "vs-dark",
          automaticLayout: true,
          minimap: { enabled: false },
          fontSize: 13,
          fontFamily: "Menlo, Monaco, monospace",
          scrollBeyondLastLine: false
        });
        editor.onDidChangeModelContent(function () {
          post({ event: "dirty", value: editor.getValue() !== lastSaved });
        });
        editor.addAction({
          id: "codeos.save",
          label: "Save File",
          keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS],
          run: function () { codeosRequestSave(); }
        });
        post({ event: "ready" });
      });

      function codeosOpen(args) {
        if (!editor) { return; }
        if (current) { current.dispose(); }
        current = monaco.editor.createModel(args[0], args[1]);
        editor.setModel(current);
        lastSaved = args[0];
        post({ event: "dirty", value: false });
      }

      function codeosRequestSave() {
        if (!editor) { return; }
        post({ event: "save", text: editor.getValue() });
      }

      function codeosMarkSaved() {
        lastSaved = editor.getValue();
        post({ event: "dirty", value: false });
      }
    </script>
    </body>
    </html>
    """#

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: MonacoEditor?
        weak var webView: WKWebView?
        var documentID = ""
        var pendingText = ""
        var pendingLanguage = "plaintext"
        var lastSaveTick = 0
        private var ready = false

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let event = body["event"] as? String,
                  let parent else { return }
            switch event {
            case "ready":
                ready = true
                push()
            case "dirty":
                parent.onDirty((body["value"] as? Bool) ?? true)
            case "save":
                let text = (body["text"] as? String) ?? ""
                if let error = parent.onSave(text) {
                    let alert = NSAlert()
                    alert.messageText = "Could not save"
                    alert.informativeText = error
                    alert.runModal()
                } else {
                    run("codeosMarkSaved()")
                }
            default:
                break
            }
        }

        func push() {
            guard ready else { return }
            guard let data = try? JSONSerialization.data(withJSONObject: [pendingText, pendingLanguage]),
                  let json = String(data: data, encoding: .utf8) else { return }
            run("codeosOpen(" + json + ")")
        }

        func run(_ script: String) {
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    /// Holds the coordinator weakly, so the web view's handler never keeps the editor alive.
    final class ScriptProxy: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?

        init(_ target: WKScriptMessageHandler) {
            self.target = target
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(controller, didReceive: message)
        }
    }
}
