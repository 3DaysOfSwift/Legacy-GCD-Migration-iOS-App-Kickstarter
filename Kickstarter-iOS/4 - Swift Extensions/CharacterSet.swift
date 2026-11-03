import Foundation

public extension CharacterSet {
  static func ksr_decimalSeparators() -> CharacterSet {
    return CharacterSet(charactersIn: LocalizationValues.currentLocale.decimalSeparator ?? "")
  }

  static func ksr_numericCharacters() -> CharacterSet {
    return CharacterSet.decimalDigits
  }
}
