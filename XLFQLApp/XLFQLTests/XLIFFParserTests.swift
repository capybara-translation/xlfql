import XCTest

final class XLIFFParserTests: XCTestCase {

    private func parse(_ xml: String) throws -> [XLIFFFile] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.xlf")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try XLIFFParser().parse(contentsOf: url)
    }

    private func wrap(_ body: String, sourceLang: String = "en", targetLang: String = "ja", original: String = "test.txt") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <xliff version="1.2" xmlns="urn:oasis:names:tc:xliff:document:1.2">
          <file source-language="\(sourceLang)" target-language="\(targetLang)" datatype="plaintext" original="\(original)">
            <body>
            \(body)
            </body>
          </file>
        </xliff>
        """
    }

    // MARK: - Pattern A: Basic trans-unit

    func testBasicTransUnit() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source>Hello</source>
              <target>こんにちは</target>
            </trans-unit>
        """)
        let files = try parse(xml)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].sourceLanguage, "en")
        XCTAssertEqual(files[0].targetLanguage, "ja")
        XCTAssertEqual(files[0].original, "test.txt")
        XCTAssertEqual(files[0].transUnits.count, 1)

        let unit = files[0].transUnits[0]
        XCTAssertEqual(unit.id, "tu1")
        XCTAssertEqual(unit.source, "Hello")
        XCTAssertEqual(unit.target, "こんにちは")
        XCTAssertNil(unit.note)
    }

    func testMissingTarget() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source>Untranslated</source>
            </trans-unit>
        """)
        let files = try parse(xml)
        let unit = files[0].transUnits[0]

        XCTAssertEqual(unit.source, "Untranslated")
        XCTAssertNil(unit.target)
    }

    func testNote() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source>Hello</source>
              <target>こんにちは</target>
              <note>Greeting message</note>
            </trans-unit>
        """)
        let files = try parse(xml)
        let unit = files[0].transUnits[0]

        XCTAssertEqual(unit.note, "Greeting message")
    }

    func testMultipleTransUnits() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source>Hello</source>
              <target>こんにちは</target>
            </trans-unit>
            <trans-unit id="tu2">
              <source>Goodbye</source>
              <target>さようなら</target>
            </trans-unit>
            <trans-unit id="tu3">
              <source>Thanks</source>
              <target>ありがとう</target>
            </trans-unit>
        """)
        let files = try parse(xml)

        XCTAssertEqual(files[0].transUnits.count, 3)
        XCTAssertEqual(files[0].transUnits[0].id, "tu1")
        XCTAssertEqual(files[0].transUnits[1].id, "tu2")
        XCTAssertEqual(files[0].transUnits[2].id, "tu3")
    }

    // MARK: - Multiple files

    func testMultipleFiles() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <xliff version="1.2" xmlns="urn:oasis:names:tc:xliff:document:1.2">
          <file source-language="en" target-language="ja" datatype="plaintext" original="file1.txt">
            <body>
              <trans-unit id="tu1">
                <source>Hello</source>
                <target>こんにちは</target>
              </trans-unit>
            </body>
          </file>
          <file source-language="en" target-language="fr" datatype="plaintext" original="file2.txt">
            <body>
              <trans-unit id="tu1">
                <source>Hello</source>
                <target>Bonjour</target>
              </trans-unit>
            </body>
          </file>
        </xliff>
        """
        let files = try parse(xml)

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].original, "file1.txt")
        XCTAssertEqual(files[0].targetLanguage, "ja")
        XCTAssertEqual(files[1].original, "file2.txt")
        XCTAssertEqual(files[1].targetLanguage, "fr")
        XCTAssertEqual(files[1].transUnits[0].target, "Bonjour")
    }

    // MARK: - Inline tags

    func testInlineTagG() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source>Click <g id="1">here</g> to continue</source>
              <target><g id="1">ここ</g>をクリックして続行</target>
            </trans-unit>
        """)
        let unit = try parse(xml)[0].transUnits[0]

        XCTAssertEqual(unit.source, "Click <g id=\"1\">here</g> to continue")
        XCTAssertEqual(unit.target, "<g id=\"1\">ここ</g>をクリックして続行")
    }

    func testInlineTagX() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source>Line 1<x id="1"/>Line 2</source>
              <target>行1<x id="1"/>行2</target>
            </trans-unit>
        """)
        let unit = try parse(xml)[0].transUnits[0]

        XCTAssertEqual(unit.source, "Line 1<x id=\"1\"></x>Line 2")
        XCTAssertEqual(unit.target, "行1<x id=\"1\"></x>行2")
    }

    func testInlineTagPh() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source>Hello <ph id="1">{0}</ph>, welcome</source>
              <target>こんにちは <ph id="1">{0}</ph>、ようこそ</target>
            </trans-unit>
        """)
        let unit = try parse(xml)[0].transUnits[0]

        XCTAssertEqual(unit.source, "Hello <ph id=\"1\">{0}</ph>, welcome")
        XCTAssertEqual(unit.target, "こんにちは <ph id=\"1\">{0}</ph>、ようこそ")
    }

    func testInlineTagBptEpt() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source><bpt id="1">&lt;b&gt;</bpt>Bold<ept id="1">&lt;/b&gt;</ept> normal</source>
              <target><bpt id="1">&lt;b&gt;</bpt>太字<ept id="1">&lt;/b&gt;</ept> 通常</target>
            </trans-unit>
        """)
        let unit = try parse(xml)[0].transUnits[0]

        XCTAssertTrue(unit.source.contains("<bpt id=\"1\">"))
        XCTAssertTrue(unit.source.contains("</bpt>"))
        XCTAssertTrue(unit.source.contains("<ept id=\"1\">"))
        XCTAssertTrue(unit.source.contains("</ept>"))
    }

    // MARK: - Pattern B: seg-source + mrk

    func testSegSourceWithMid() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source>This is an apple. That is a melon.</source>
              <seg-source>
                <mrk mtype="seg" mid="m1">This is an apple.</mrk>
                <mrk mtype="seg" mid="m2">That is a melon.</mrk>
              </seg-source>
              <target>
                <mrk mtype="seg" mid="m1">これはりんごです。</mrk>
                <mrk mtype="seg" mid="m2">あれはメロンです。</mrk>
              </target>
            </trans-unit>
        """)
        let units = try parse(xml)[0].transUnits

        XCTAssertEqual(units.count, 2)

        XCTAssertEqual(units[0].id, "tu1#m1")
        XCTAssertEqual(units[0].source, "This is an apple.")
        XCTAssertEqual(units[0].target, "これはりんごです。")

        XCTAssertEqual(units[1].id, "tu1#m2")
        XCTAssertEqual(units[1].source, "That is a melon.")
        XCTAssertEqual(units[1].target, "あれはメロンです。")
    }

    func testSegSourceWithoutMid() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source>First. Second. Third.</source>
              <seg-source>
                <mrk mtype="seg">First.</mrk>
                <mrk mtype="seg">Second.</mrk>
                <mrk mtype="seg">Third.</mrk>
              </seg-source>
              <target>
                <mrk mtype="seg">最初。</mrk>
                <mrk mtype="seg">2番目。</mrk>
                <mrk mtype="seg">3番目。</mrk>
              </target>
            </trans-unit>
        """)
        let units = try parse(xml)[0].transUnits

        XCTAssertEqual(units.count, 3)
        XCTAssertEqual(units[0].id, "tu1#0")
        XCTAssertEqual(units[1].id, "tu1#1")
        XCTAssertEqual(units[2].id, "tu1#2")
        XCTAssertEqual(units[0].source, "First.")
        XCTAssertEqual(units[0].target, "最初。")
    }

    func testSegSourceNoteIsShared() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source>A. B.</source>
              <seg-source>
                <mrk mtype="seg" mid="s1">A.</mrk>
                <mrk mtype="seg" mid="s2">B.</mrk>
              </seg-source>
              <target>
                <mrk mtype="seg" mid="s1">あ。</mrk>
                <mrk mtype="seg" mid="s2">い。</mrk>
              </target>
              <note>Shared note</note>
            </trans-unit>
        """)
        let units = try parse(xml)[0].transUnits

        XCTAssertEqual(units[0].note, "Shared note")
        XCTAssertEqual(units[1].note, "Shared note")
    }

    func testSegSourceMissingTarget() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source>A. B.</source>
              <seg-source>
                <mrk mtype="seg" mid="s1">A.</mrk>
                <mrk mtype="seg" mid="s2">B.</mrk>
              </seg-source>
              <target>
                <mrk mtype="seg" mid="s1">あ。</mrk>
              </target>
            </trans-unit>
        """)
        let units = try parse(xml)[0].transUnits

        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units[0].target, "あ。")
        XCTAssertNil(units[1].target)
    }

    // MARK: - Edge cases

    func testXMLEntities() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source>A &amp; B &lt;C&gt;</source>
              <target>A &amp; B &lt;C&gt;</target>
            </trans-unit>
        """)
        let unit = try parse(xml)[0].transUnits[0]

        XCTAssertEqual(unit.source, "A & B <C>")
        XCTAssertEqual(unit.target, "A & B <C>")
    }

    func testMultilineText() throws {
        let xml = wrap("""
            <trans-unit id="tu1">
              <source>Line 1
        Line 2
        Line 3</source>
              <target>行1
        行2
        行3</target>
            </trans-unit>
        """)
        let unit = try parse(xml)[0].transUnits[0]

        XCTAssertTrue(unit.source.contains("\n"))
        XCTAssertTrue(unit.target!.contains("\n"))
    }

    func testEmptyFile() throws {
        let xml = wrap("")
        let files = try parse(xml)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].transUnits.count, 0)
    }

    func testMissingTargetLanguage() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <xliff version="1.2" xmlns="urn:oasis:names:tc:xliff:document:1.2">
          <file source-language="en" datatype="plaintext" original="test.txt">
            <body>
              <trans-unit id="tu1">
                <source>Hello</source>
              </trans-unit>
            </body>
          </file>
        </xliff>
        """
        let files = try parse(xml)

        XCTAssertNil(files[0].targetLanguage)
    }
}
