import XCTest
@testable import StudyTable

final class ResourceCatalogTests: XCTestCase {
    private func translation(_ id: String, delivery: TranslationDelivery) -> TranslationInfo {
        TranslationInfo(id: id, name: "Fixture", delivery: delivery, licenseSummary: "Fixture", attribution: "Fixture")
    }

    func testOnlyActualOfflineDeliveryShowsInstalled() {
        let entries = [translation("BSB", delivery: .bundled), translation("ASV", delivery: .installedPack),
                       translation("ESV", delivery: .online(.esv)), translation("NASB", delivery: .licensePackRequired)]
        XCTAssertEqual(ResourceCatalog.availability(of: "BSB", in: entries), .included)
        XCTAssertEqual(ResourceCatalog.availability(of: "ASV", in: entries), .installed)
        XCTAssertEqual(ResourceCatalog.availability(of: "YLT", in: entries), .availableToDownload)
        XCTAssertEqual(ResourceCatalog.availability(of: "ESV", in: entries), .unavailable)
        XCTAssertEqual(ResourceCatalog.availability(of: "NASB", in: entries), .unavailable)
    }

    func testMissingResourcesAreNotInventedDownloads() {
        for edition in BibleDownload.catalog {
            XCTAssertEqual(ResourceCatalog.availability(of: edition.id, in: []), .availableToDownload)
        }
        for id in ["BSB", "KJV", "WEB", "ESV", "NKJV", "NASB", "unknown"] {
            XCTAssertEqual(ResourceCatalog.availability(of: id, in: []), .unavailable)
        }
    }

    func testManualPackDoesNotNeedToBeInFreeDownloadCatalog() {
        XCTAssertEqual(ResourceCatalog.availability(of: "NASB", in: [translation("NASB", delivery: .installedPack)]), .installed)
    }

    func testRightsReviewRemainsSeparateInPrivateAndPublicBuilds() throws {
        for includesHCF in [true, false] {
            let review = try XCTUnwrap(ResourceCatalog.resources(in: .rightsReview, includesHCF: includesHCF).first { $0.id == "hcf" })
            XCTAssertEqual(review.access, .rightsReview)
            XCTAssertFalse(ResourceCatalog.resources(in: .included, includesHCF: includesHCF).contains { $0.id == "hcf" })
            XCTAssertEqual(review.sourceURL.lastPathComponent, "LICENSE")
        }
        let included = try XCTUnwrap(ResourceCatalog.resources(in: .rightsReview, includesHCF: true).first)
        let withheld = try XCTUnwrap(ResourceCatalog.resources(in: .rightsReview, includesHCF: false).first)
        XCTAssertTrue(included.detail.contains("Present in this beta"))
        XCTAssertTrue(withheld.detail.contains("Not included in this build"))
        XCTAssertFalse(withheld.detail.contains("Present in this beta"))
    }

    func testCatalogueHasUniqueIDsAndPrimaryHTTPSLinks() {
        XCTAssertEqual(Set(ResourceCatalog.resources.map(\.id)).count, ResourceCatalog.resources.count)
        XCTAssertEqual(Set(ResourceCatalog.resources.map(\.access)), Set(ResourceAccessGroup.allCases))
        for resource in ResourceCatalog.resources {
            XCTAssertEqual(resource.sourceURL.scheme, "https", resource.id)
            XCTAssertNotNil(resource.sourceURL.host, resource.id)
            XCTAssertFalse(resource.rights.isEmpty, resource.id)
        }
    }

    func testReadingCountComesFromBundledCatalogue() throws {
        let url = try XCTUnwrap(AppResources.url("PuritanLibrary/catalog.json"))
        let catalogue = try JSONDecoder().decode(PuritanLibraryCatalogue.self, from: Data(contentsOf: url))
        XCTAssertEqual(ResourceCatalog.readingWorkCount, catalogue.works.count)
        XCTAssertGreaterThan(catalogue.works.count, 0)
    }
}
