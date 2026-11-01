import Foundation
import libxml2

/// 用 libxml2 跑 XPath。支持「在某个节点下查询」，这是 Kazumi 规则的语义：
/// 规则里写 `//a`，实际含义是「在当前行内找 a」，等价于相对路径 `.//a`。
final class XPathDoc {

    struct Hit {
        let node: xmlNodePtr
        let text: String
        let href: String?
        let src: String?
    }

    private let doc: htmlDocPtr

    init?(html: String) {
        guard let data = html.data(using: .utf8) else { return nil }
        var bytes = [UInt8](data)
        guard let d = bytes.withUnsafeMutableBufferPointer({ buf -> htmlDocPtr? in
            guard let base = buf.baseAddress else { return nil }
            return htmlReadMemory(UnsafePointer<CChar>(OpaquePointer(base)),
                                  Int32(buf.count), nil, "UTF-8",
                                  Int32(HTML_PARSE_RECOVER.rawValue
                                        | HTML_PARSE_NOERROR.rawValue
                                        | HTML_PARSE_NOWARNING.rawValue))
        }) else { return nil }
        self.doc = d
    }

    deinit { xmlFreeDoc(doc) }

    /// 全局查询
    func query(_ xpath: String) -> [Hit] {
        run(xpath, context: nil)
    }

    /// 在指定节点下查询：`//x` 会被当成 `.//x`
    func query(in node: xmlNodePtr, _ xpath: String) -> [Hit] {
        run(xpath, context: node)
    }

    private func run(_ xpath: String, context: xmlNodePtr?) -> [Hit] {
        let expr = (context != nil && xpath.hasPrefix("//"))
            ? "." + xpath
            : xpath

        guard let ctx = xmlXPathNewContext(doc) else { return [] }
        defer { xmlXPathFreeContext(ctx) }
        if let context { ctx.pointee.node = context }

        guard let obj = xmlXPathEvalExpression(expr, ctx) else { return [] }
        defer { xmlXPathFreeObject(obj) }

        guard let nodes = obj.pointee.nodesetval,
              let tab = nodes.pointee.nodeTab else { return [] }

        var out: [Hit] = []
        for i in 0..<Int(nodes.pointee.nodeNr) {
            guard let n = tab[i] else { continue }
            let content = xmlNodeGetContent(n).map { String(cString: $0) } ?? ""
            var href: String? = nil
            var src: String? = nil
            if n.pointee.type == XML_ELEMENT_NODE {
                for attr in ["href", "src", "data-src", "data-original"] {
                    if let raw = xmlGetProp(n, attr) {
                        let v = String(cString: raw)
                        xmlFree(raw)
                        if attr == "href" { href = v } else if src == nil { src = v }
                    }
                }
            }
            out.append(Hit(node: n,
                           text: content.trimmingCharacters(in: .whitespacesAndNewlines),
                           href: href,
                           src: src))
        }
        return out
    }
}
