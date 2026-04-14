import Foundation

struct TransUnit {
    let id: String
    let source: String
    let target: String?
    let note: String?
}

struct XLIFFFile {
    let original: String
    let sourceLanguage: String
    let targetLanguage: String?
    let transUnits: [TransUnit]
}

final class XLIFFParser: NSObject, XMLParserDelegate {

    private var files: [XLIFFFile] = []

    // Current file attributes
    private var currentOriginal = ""
    private var currentSourceLang = ""
    private var currentTargetLang: String?
    private var currentTransUnits: [TransUnit] = []

    // Current trans-unit
    private var currentTransUnitId = ""
    private var currentSource = ""
    private var currentTarget: String?
    private var currentNote: String?
    private var currentSdlCommentIds: [String] = []

    // Segmentation (Pattern B)
    private var segSourceMarks: [(mid: String, text: String)] = []
    private var targetMarks: [(mid: String, text: String)] = []
    private var hasSegSource = false

    // Current mrk
    private var currentMrkMid: String?
    private var currentMrkText = ""
    private var mrkAutoIndex = 0
    private var mrkDepth = 0
    private var mrkKindStack: [Bool] = [] // true = seg boundary, false = visible marker
    private var inMrk: Bool { mrkDepth > 0 }

    // sdlxliff comment definitions (<doc-info>/<cmt-defs>/<cmt-def>/<Comments>/<Comment>)
    private var commentsById: [String: String] = [:]
    private var currentCmtDefId: String?
    private var inCmtDefComment = false
    private var cmtDefText = ""
    private var inDocInfo = false

    // sdlxliff per-segment comment IDs: collected inside each seg mrk,
    // flushed to the emitted TransUnit for that mid only.
    private var segCommentIdsByMid: [String: [String]] = [:]
    private var currentSegCommentIds: [String] = []

    // Parsing state
    private var inTransUnit = false
    private var inSource = false
    private var inTarget = false
    private var inSegSource = false
    private var inNote = false
    private var inAltTrans = false
    private var currentText = ""

    // Inline elements rendered as visible tag markers
    private static let visibleInlineElements: Set<String> = [
        "g", "x", "bx", "ex", "bpt", "ept", "ph", "it", "sub"
    ]

    func parse(contentsOf url: URL) throws -> [XLIFFFile] {
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false

        resetState()

        guard parser.parse() else {
            if let error = parser.parserError {
                throw error
            }
            throw NSError(domain: "XLIFFParser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to parse XLIFF"])
        }

        return files
    }

    private func resetState() {
        files = []
        currentOriginal = ""
        currentSourceLang = ""
        currentTargetLang = nil
        currentTransUnits = []
        currentTransUnitId = ""
        currentSource = ""
        currentTarget = nil
        currentNote = nil
        currentSdlCommentIds = []
        segSourceMarks = []
        targetMarks = []
        hasSegSource = false
        currentMrkMid = nil
        currentMrkText = ""
        mrkAutoIndex = 0
        mrkDepth = 0
        mrkKindStack = []
        commentsById = [:]
        currentCmtDefId = nil
        inCmtDefComment = false
        cmtDefText = ""
        inDocInfo = false
        segCommentIdsByMid = [:]
        currentSegCommentIds = []
        inTransUnit = false
        inSource = false
        inTarget = false
        inSegSource = false
        inNote = false
        inAltTrans = false
        currentText = ""
    }

    private func appendInlineMarkup(_ s: String) {
        if mrkDepth > 0 {
            currentMrkText += s
        } else if inSource || inTarget {
            currentText += s
        }
    }

    private func mergeNote(_ note: String?, sdlCommentIds: [String]) -> String? {
        let sdlText = sdlCommentIds
            .compactMap { commentsById[$0] }
            .joined(separator: "\n")
        switch (note, sdlText.isEmpty) {
        case (let n?, true): return n
        case (nil, false): return sdlText
        case (let n?, false): return "\(n)\n\(sdlText)"
        case (nil, true): return nil
        }
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName {
        case "doc-info":
            inDocInfo = true

        case "file":
            currentOriginal = attributeDict["original"] ?? ""
            currentSourceLang = attributeDict["source-language"] ?? ""
            currentTargetLang = attributeDict["target-language"]
            currentTransUnits = []
            // NOTE: commentsById is intentionally NOT reset here. In sdlxliff,
            // <doc-info>/<cmt-defs> is a sibling of <file> (not a child), so the
            // comment dictionary populated before the first <file> must persist.

        case "trans-unit":
            inTransUnit = true
            currentTransUnitId = attributeDict["id"] ?? ""
            currentSource = ""
            currentTarget = nil
            currentNote = nil
            currentSdlCommentIds = []
            segCommentIdsByMid = [:]
            currentSegCommentIds = []
            segSourceMarks = []
            targetMarks = []
            hasSegSource = false
            mrkAutoIndex = 0

        case "alt-trans":
            if inTransUnit {
                inAltTrans = true
            }

        case "seg-source":
            if inTransUnit && !inAltTrans {
                inSegSource = true
                hasSegSource = true
                mrkAutoIndex = 0
            }

        case "source":
            if inTransUnit && !inAltTrans && !inSegSource && !inMrk {
                inSource = true
                currentText = ""
            }

        case "target":
            if inTransUnit && !inAltTrans && !inMrk {
                inTarget = true
                currentText = ""
                if hasSegSource {
                    mrkAutoIndex = 0
                }
            }

        case "mrk":
            if inTransUnit && !inAltTrans && !inNote {
                let mtype = attributeDict["mtype"] ?? ""
                let isSeg = (mtype == "seg") && (inSegSource || inTarget) && mrkDepth == 0
                mrkKindStack.append(isSeg)
                if isSeg {
                    currentMrkMid = attributeDict["mid"]
                    currentMrkText = ""
                    currentSegCommentIds = []
                    mrkDepth += 1
                } else {
                    if mtype == "x-sdl-comment", let cid = attributeDict["sdl:cid"] {
                        currentSegCommentIds.append(cid)
                    }
                    var tagText = "<mrk"
                    if !mtype.isEmpty { tagText += " mtype=\"\(mtype)\"" }
                    if let mid = attributeDict["mid"] { tagText += " mid=\"\(mid)\"" }
                    tagText += ">"
                    appendInlineMarkup(tagText)
                }
            }

        case "note":
            if inTransUnit && !inAltTrans {
                inNote = true
                currentText = ""
            }

        case "cmt-def":
            if inDocInfo {
                currentCmtDefId = attributeDict["id"]
            }

        case "Comment":
            if inDocInfo && currentCmtDefId != nil {
                inCmtDefComment = true
                cmtDefText = ""
            }

        case "cmt":
            // sdlxliff trans-unit level comment reference: <sdl:cmt id="..."/>
            if inTransUnit && !inAltTrans, let id = attributeDict["id"] {
                currentSdlCommentIds.append(id)
            }

        default:
            // Visible inline tags inside text-bearing elements
            if (inSource || inTarget || inMrk) && Self.visibleInlineElements.contains(localName) {
                var tagText = "<\(localName)"
                if let id = attributeDict["id"] {
                    tagText += " id=\"\(id)\""
                }
                tagText += ">"

                if inMrk {
                    currentMrkText += tagText
                } else {
                    currentText += tagText
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inCmtDefComment {
            cmtDefText += string
        } else if inMrk {
            currentMrkText += string
        } else if inSource || inTarget || inNote {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName {
        case "source":
            if inTransUnit && inSource {
                currentSource = currentText
                inSource = false
            }

        case "target":
            if inTransUnit && inTarget {
                if !hasSegSource {
                    currentTarget = currentText
                }
                inTarget = false
            }

        case "seg-source":
            inSegSource = false

        case "mrk":
            if let wasSeg = mrkKindStack.popLast() {
                if wasSeg {
                    mrkDepth -= 1
                    let mid = currentMrkMid ?? "\(mrkAutoIndex)"
                    mrkAutoIndex += 1
                    if inSegSource {
                        segSourceMarks.append((mid: mid, text: currentMrkText))
                    } else if inTarget {
                        targetMarks.append((mid: mid, text: currentMrkText))
                        if !currentSegCommentIds.isEmpty {
                            let existing = segCommentIdsByMid[mid] ?? []
                            segCommentIdsByMid[mid] = existing + currentSegCommentIds
                        }
                    }
                    currentSegCommentIds = []
                    currentMrkMid = nil
                } else {
                    appendInlineMarkup("</mrk>")
                }
            }

        case "note":
            if inTransUnit && inNote {
                currentNote = currentText
                inNote = false
            }

        case "Comment":
            if inCmtDefComment, let id = currentCmtDefId {
                if let existing = commentsById[id] {
                    commentsById[id] = "\(existing)\n\(cmtDefText)"
                } else {
                    commentsById[id] = cmtDefText
                }
                inCmtDefComment = false
            }

        case "cmt-def":
            if inDocInfo {
                currentCmtDefId = nil
            }

        case "doc-info":
            inDocInfo = false

        case "trans-unit":
            // Trans-unit-level sdl:cmt applies to all emitted segments.
            // Segment-level x-sdl-comment applies only to its own seg mid.
            if hasSegSource && !segSourceMarks.isEmpty {
                let targetByMid = Dictionary(targetMarks.map { ($0.mid, $0.text) },
                                              uniquingKeysWith: { _, last in last })
                for mark in segSourceMarks {
                    let segIds = (segCommentIdsByMid[mark.mid] ?? [])
                    let combinedIds = currentSdlCommentIds + segIds
                    let unit = TransUnit(
                        id: "\(currentTransUnitId)#\(mark.mid)",
                        source: mark.text,
                        target: targetByMid[mark.mid],
                        note: mergeNote(currentNote, sdlCommentIds: combinedIds)
                    )
                    currentTransUnits.append(unit)
                }
            } else {
                // Pattern A: flatten any segment-level comments into the single unit.
                let allSegIds = segCommentIdsByMid.values.flatMap { $0 }
                let combinedIds = currentSdlCommentIds + allSegIds
                let unit = TransUnit(id: currentTransUnitId,
                                     source: currentSource,
                                     target: currentTarget,
                                     note: mergeNote(currentNote, sdlCommentIds: combinedIds))
                currentTransUnits.append(unit)
            }
            currentSdlCommentIds = []
            segCommentIdsByMid = [:]
            inTransUnit = false

        case "alt-trans":
            if inAltTrans {
                inAltTrans = false
            }

        case "file":
            let file = XLIFFFile(original: currentOriginal,
                                 sourceLanguage: currentSourceLang,
                                 targetLanguage: currentTargetLang,
                                 transUnits: currentTransUnits)
            files.append(file)

        default:
            // Closing visible inline tags
            if (inSource || inTarget || inMrk) && Self.visibleInlineElements.contains(localName) {
                if inMrk {
                    currentMrkText += "</\(localName)>"
                } else {
                    currentText += "</\(localName)>"
                }
            }
        }
    }
}
