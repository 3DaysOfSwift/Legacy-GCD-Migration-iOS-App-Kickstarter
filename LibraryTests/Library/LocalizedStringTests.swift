@testable import Library
@testable import LibraryTestHelpers
import XCTest

@MainActor
class LocalizedStringTests: XCTestCase {
  fileprivate let mockBundle = MockBundle()

  func testNumberLocaleRestoresAfterNestedEnvironmentChanges() async {
    let original = LocalizationValues.currentLocale
    await withEnvironment(locale: Locale(identifier: "de_DE")) {
      let german = Format.wholeNumber(12345, locale: Locale(identifier: "de_DE"))
      let background = await Task.detached { Format.wholeNumber(12345) }.value
      XCTAssertEqual(background, german)
      withEnvironment(locale: Locale(identifier: "en_US")) {
        XCTAssertEqual(Format.wholeNumber(12345), "12,345")
      }
      XCTAssertEqual(Format.wholeNumber(12345), german)
    }
    XCTAssertEqual(LocalizationValues.currentLocale, original)
  }

  func testExplicitNumberEnvironmentDoesNotChangePublishedLocale() {
    withEnvironment(locale: Locale(identifier: "en_US")) {
      let german = Environment(locale: Locale(identifier: "de_DE"))
      XCTAssertEqual(Format.wholeNumber(12345, env: german), "12.345")
      XCTAssertEqual(Format.wholeNumber(12345), "12,345")
    }
  }

  func testNestedLanguageChangesRestoreThePreviousLanguage() {
    let original = LocalizationValues.currentLanguage
    withEnvironment(language: .de) {
      XCTAssertEqual("de_world", localizedString(key: "hello", bundle: self.mockBundle))
      withEnvironment(language: .en) {
        XCTAssertEqual(.en, LocalizationValues.currentLanguage)
      }
      XCTAssertEqual("de_world", localizedString(key: "hello", bundle: self.mockBundle))
    }
    XCTAssertEqual(original, LocalizationValues.currentLanguage)
  }

  func testExplicitEnvironmentDoesNotChangeDefaultLanguage() {
    withEnvironment(language: .en) {
      let german = Environment(language: .de)
      XCTAssertEqual("de_world", localizedString(key: "hello", env: german, bundle: self.mockBundle))
      XCTAssertEqual(.en, LocalizationValues.currentLanguage)
    }
  }

  func testBackgroundLocalizationUsesPublishedLanguage() async {
    await withEnvironment(language: .de) {
      let expected = localizedString(key: "hello", bundle: self.mockBundle)
      let actual = await Task.detached {
        localizedString(key: "hello", bundle: MockBundle())
      }.value
      XCTAssertEqual(expected, actual)
    }
  }

  func testLocalizedPostalCode_USA() {
    withEnvironment(locale: Locale(identifier: "de_US")) {
      XCTAssertEqual("Zip code", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "en_US")) {
      XCTAssertEqual("Zip code", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "es_US")) {
      XCTAssertEqual("Zip code", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "fr_US")) {
      XCTAssertEqual("Zip code", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "ja_US")) {
      XCTAssertEqual("Zip code", localizedPostalCode())
    }
  }

  func testLocalizedPostalCode_Canada() {
    withEnvironment(locale: Locale(identifier: "de_CA")) {
      XCTAssertEqual("Postal code", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "en_CA")) {
      XCTAssertEqual("Postal code", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "es_CA")) {
      XCTAssertEqual("Postal code", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "fr_CA")) {
      XCTAssertEqual("Postal code", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "ja_CA")) {
      XCTAssertEqual("Postal code", localizedPostalCode())
    }
  }

  func testLocalizedPostalCode_Other() {
    withEnvironment(locale: Locale(identifier: "de_AU")) {
      XCTAssertEqual("Postcode", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "en_GB")) {
      XCTAssertEqual("Postcode", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "es_FR")) {
      XCTAssertEqual("Postcode", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "fr_AT")) {
      XCTAssertEqual("Postcode", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "ja_CH")) {
      XCTAssertEqual("Postcode", localizedPostalCode())
    }
  }

  func testLocalizedPostalCode_No_Region() {
    withEnvironment(locale: Locale(identifier: "de")) {
      XCTAssertEqual("Postcode", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "en")) {
      XCTAssertEqual("Postcode", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "es")) {
      XCTAssertEqual("Postcode", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "fr")) {
      XCTAssertEqual("Postcode", localizedPostalCode())
    }

    withEnvironment(locale: Locale(identifier: "ja")) {
      XCTAssertEqual("Postcode", localizedPostalCode())
    }
  }

  func testLocalizingInGerman() {
    withEnvironment(language: .de) {
      XCTAssertEqual("de_world", localizedString(key: "hello", bundle: self.mockBundle))
      XCTAssertEqual("Hello", localizedString(key: "hello_", defaultValue: "Hello", bundle: self.mockBundle))
      XCTAssertEqual("", localizedString(key: "hello_", bundle: self.mockBundle))

      XCTAssertEqual(
        "de_hello A B",
        localizedString(key: "hello_format", substitutions: ["a": "A", "b": "B"], bundle: self.mockBundle)
      )

      XCTAssertEqual(
        "",
        localizedString(key: "echo", bundle: self.mockBundle),
        "When key/value are equal we should return an empty string"
      )
    }
  }

  func testLocalizedStringWithCount() {
    withEnvironment(language: .en, mainBundle: MockBundle()) {
      XCTAssertEqual(localizedString(key: "test_count", count: 0, bundle: self.mockBundle), "zero")

      XCTAssertEqual(localizedString(key: "test_count", count: 1, bundle: self.mockBundle), "one")

      XCTAssertEqual(localizedString(key: "test_count", count: 2, bundle: self.mockBundle), "two")

      XCTAssertEqual(
        localizedString(
          key: "test_count",
          count: 3,
          substitutions: ["the_count": "3"],
          bundle: self.mockBundle
        ),
        "3 few"
      )

      XCTAssertEqual(
        localizedString(
          key: "test_count",
          count: 4,
          substitutions: ["the_count": "4"],
          bundle: self.mockBundle
        ),
        "4 few"
      )

      XCTAssertEqual(
        localizedString(
          key: "test_count",
          count: 5,
          substitutions: ["the_count": "5"],
          bundle: self.mockBundle
        ),
        "5 few"
      )

      XCTAssertEqual(
        localizedString(
          key: "test_count",
          count: 6,
          substitutions: ["the_count": "6"],
          bundle: self.mockBundle
        ),
        "6 many"
      )
    }
  }

  func testMissingKeyWithCount() {
    withEnvironment(language: .en, mainBundle: MockBundle()) {
      XCTAssertEqual(
        "10 backers",
        localizedString(
          key: "missing.key",
          defaultValue: "%{count} backers",
          count: 10,
          substitutions: ["count": "10"],
          bundle: self.mockBundle
        )
      )
    }
  }
}
