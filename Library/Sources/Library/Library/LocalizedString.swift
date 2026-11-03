import Foundation
import Prelude
import Synchronization

@MainActor
public func localizedPostalCode() -> String {
  // 🙏 Inspired by Kristina Fox
  // https://speakerdeck.com/krstnfx/internationalizing-your-app?slide=37
  switch AppEnvironment.current.locale.regionCode {
  // 🇺🇸
  case .some("US"): return Strings.Zip_code()
  // 🇨🇦
  case .some("CA"): return Strings.Postal_code()
  // 🌍
  default: return Strings.Postcode()
  }
}

/**
 Finds a localized string for a provided key and interpolates it with substitutions.

 - parameters:
   - key:           The key of the string to find in a bundle.
   - defaultValue:  Optional value to use in case a string could not be found for the provided key.
   - substitutions: A dictionary of key/value substitutions to be made.
   - env:           An app environment to derive the language from.

 - returns: The localized string. If the key does not exist the `defaultValue` will be returned,
 and if that is not specified an empty string will be returned.
 */
public func localizedString(
  key: String,
  defaultValue: String = "",
  count: Int? = nil,
  substitutions: [String: String] = [:],
  env: Environment? = nil,
  bundle: NSBundleType = stringsBundle
) -> String {
  // When a `count` is provided we need to augment the key with a pluralization suffix.
  let augmentedKey = count
    .flatMap { key + "." + keySuffixForCount($0) }
    .coalesceWith(key)

  let lprojName = lprojFileNameForLanguage(env?.language ?? LocalizationValues.currentLanguage)
  let localized = bundle.path(forResource: lprojName, ofType: "lproj")
    .flatMap(type(of: bundle).create(path:))
    .flatMap { $0.localizedString(forKey: augmentedKey, value: nil, table: nil) }
    .filter {
      // NB: `localizedStringForKey` has the annoying habit of returning the key when the key doesn't exist.
      // We filter those out and hope that we never use a value that is equal to its key.
      $0.caseInsensitiveCompare(augmentedKey) != .orderedSame
    }
    .filter { !$0.isEmpty }
    .coalesceWith(defaultValue)

  return substitute(localized, with: substitutions)
}

private func lprojFileNameForLanguage(_ language: Language) -> String {
  return language.rawValue == "en" ? "Base" : language.rawValue
}

// Returns the pluralization suffx for a count.
private func keySuffixForCount(_ count: Int) -> String {
  switch count {
  case 0:
    return "zero"
  case 1:
    return "one"
  case 2:
    return "two"
  case 3...5:
    return "few"
  default:
    return "many"
  }
}

// Performs simple string interpolation on keys of the form `%{key}`.
private func substitute(_ string: String, with substitutions: [String: String]) -> String {
  return substitutions.reduce(string) { accum, sub in
    accum.replacingOccurrences(of: "%{\(sub.0)}", with: sub.1)
  }
}

public let stringsBundle = Bundle.library

/// A value-only projection for synchronous localization, including background error descriptions.
/// AppEnvironment publishes language/locale changes; readers never access its service or session references.
internal enum LocalizationValues {
  private struct Snapshot: Sendable {
    var language: Language
    var locale: Locale
  }

  private static let values = Mutex(Snapshot(
    language: Language(languageStrings: Locale.preferredLanguages) ?? .en,
    locale: .current
  ))

  static var currentLanguage: Language { self.values.withLock { $0.language } }
  static var currentLocale: Locale { self.values.withLock { $0.locale } }

  static func update(language: Language, locale: Locale) {
    self.values.withLock { $0 = Snapshot(language: language, locale: locale) }
  }
}
