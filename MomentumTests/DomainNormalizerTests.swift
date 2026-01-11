import XCTest
@testable import Momentum

@MainActor
final class DomainNormalizerTests: XCTestCase {
    func testNormalizeAcceptsSchemeOrBareHost() {
        XCTAssertEqual(DomainNormalizer.normalize("example.com"), "example.com")
        XCTAssertEqual(DomainNormalizer.normalize("https://example.com"), "example.com")
        XCTAssertEqual(DomainNormalizer.normalize("http://example.com"), "example.com")
    }

    func testNormalizeStripsPathQueryAndWww() {
        XCTAssertEqual(
            DomainNormalizer.normalize("https://www.Example.com/path?query=1#hash"),
            "example.com",
        )
        XCTAssertEqual(DomainNormalizer.normalize("example.com/path"), "example.com")
    }

    func testNormalizeRejectsUnsupportedSchemes() {
        XCTAssertNil(DomainNormalizer.normalize("ftp://example.com"))
        XCTAssertNil(DomainNormalizer.normalize("file:///tmp/test"))
    }

    func testNormalizeRejectsInvalidHosts() {
        XCTAssertNil(DomainNormalizer.normalize("localhost"))
        XCTAssertNil(DomainNormalizer.normalize("foo..bar.com"))
        XCTAssertNil(DomainNormalizer.normalize("foo_bar.com"))
        XCTAssertNil(DomainNormalizer.normalize("foo.-bar.com"))
        XCTAssertNil(DomainNormalizer.normalize("-foo.bar.com"))
    }

    func testDomainsFromCommaSeparatedInput() {
        let result = DomainNormalizer.domains(from: "example.com, https://foo.bar/path, , www.example.com, localhost")
        XCTAssertEqual(result, ["example.com", "foo.bar", "example.com"])
    }

    func testRejectedTokensReturnsOnlyInvalidEntries() {
        let rejected = DomainNormalizer.rejectedTokens(from: "example.com, localhost, foo_bar.com")
        XCTAssertEqual(rejected, ["localhost", "foo_bar.com"])
    }

    func testProjectFormDraftAddsNormalizedDomainsAndClearsEntry() {
        var draft = ProjectFormDraft()
        draft.domainEntry = "https://example.com/path, example.com, foo.bar"
        let result = draft.addDomainEntry()

        XCTAssertEqual(draft.assignedDomains, ["example.com", "foo.bar"])
        XCTAssertEqual(draft.domainEntry, "")
        XCTAssertEqual(result.rejected, [])
    }

    func testProjectFormDraftKeepsEntryWhenNoValidDomains() {
        var draft = ProjectFormDraft()
        draft.domainEntry = "localhost, foo_bar.com"
        let result = draft.addDomainEntry()

        XCTAssertEqual(draft.assignedDomains, [])
        XCTAssertEqual(draft.domainEntry, "localhost, foo_bar.com")
        XCTAssertEqual(result.rejected, ["localhost", "foo_bar.com"])
    }
}
