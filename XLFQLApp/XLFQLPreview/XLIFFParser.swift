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

    // Segmentation (Pattern B)
    private var segSourceMarks: [(mid: String, text: String)] = []
    private var targetMarks: [(mid: String, text: String)] = []
    private var hasSegSource = false

    // Current mrk
    private var currentMrkMid: String?
    private var currentMrkText = ""
    private var mrkAutoIndex = 0

    // Parsing state
    private var inTransUnit = false
    private var inSource = false
    private var inTarget = false
    private var inSegSource = false
    private var inNote = false
    private var inMrk = false
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
        segSourceMarks = []
        targetMarks = []
        hasSegSource = false
        currentMrkMid = nil
        currentMrkText = ""
        mrkAutoIndex = 0
        inTransUnit = false
        inSource = false
        inTarget = false
        inSegSource = false
        inNote = false
        inMrk = false
        currentText = ""
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName {
        case "file":
            currentOriginal = attributeDict["original"] ?? ""
            currentSourceLang = attributeDict["source-language"] ?? ""
            currentTargetLang = attributeDict["target-language"]
            currentTransUnits = []

        case "trans-unit":
            inTransUnit = true
            currentTransUnitId = attributeDict["id"] ?? ""
            currentSource = ""
            currentTarget = nil
            currentNote = nil
            segSourceMarks = []
            targetMarks = []
            hasSegSource = false
            mrkAutoIndex = 0

        case "seg-source":
            if inTransUnit {
                inSegSource = true
                hasSegSource = true
                mrkAutoIndex = 0
            }

        case "source":
            if inTransUnit && !inSegSource && !inMrk {
                inSource = true
                currentText = ""
            }

        case "target":
            if inTransUnit && !inMrk {
                inTarget = true
                currentText = ""
                if hasSegSource {
                    mrkAutoIndex = 0
                }
            }

        case "mrk":
            if inTransUnit && (inSegSource || inTarget) {
                inMrk = true
                currentMrkMid = attributeDict["mid"]
                currentMrkText = ""
            }

        case "note":
            if inTransUnit {
                inNote = true
                currentText = ""
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
        if inMrk {
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
            if inMrk {
                let mid = currentMrkMid ?? "\(mrkAutoIndex)"
                mrkAutoIndex += 1

                if inSegSource {
                    segSourceMarks.append((mid: mid, text: currentMrkText))
                } else if inTarget {
                    targetMarks.append((mid: mid, text: currentMrkText))
                }

                inMrk = false
                currentMrkMid = nil
            }

        case "note":
            if inTransUnit && inNote {
                currentNote = currentText
                inNote = false
            }

        case "trans-unit":
            if hasSegSource && !segSourceMarks.isEmpty {
                // Pattern B: emit one TransUnit per mrk segment
                let targetByMid = Dictionary(targetMarks.map { ($0.mid, $0.text) },
                                              uniquingKeysWith: { _, last in last })
                for mark in segSourceMarks {
                    let unit = TransUnit(
                        id: "\(currentTransUnitId)#\(mark.mid)",
                        source: mark.text,
                        target: targetByMid[mark.mid],
                        note: currentNote
                    )
                    currentTransUnits.append(unit)
                }
            } else {
                // Pattern A: single TransUnit
                let unit = TransUnit(id: currentTransUnitId,
                                     source: currentSource,
                                     target: currentTarget,
                                     note: currentNote)
                currentTransUnits.append(unit)
            }
            inTransUnit = false

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
