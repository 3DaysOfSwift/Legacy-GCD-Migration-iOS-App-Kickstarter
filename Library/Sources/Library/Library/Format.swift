import Foundation
import GraphAPI
import KsApi
import Prelude
import Synchronization

public let UTCTimeZone = TimeZone(secondsFromGMT: 0)!

public enum Format {
  /**
   Formats an int into a string.

   - parameter x:   An integer.
   - parameter env: An (optional) environment.

   - returns: A formatted string.
   */
  public static func wholeNumber(_ x: Int, env: Environment = AppEnvironment.current) -> String {
    self.wholeNumber(x, locale: env.locale)
  }

  public static func wholeNumber(_ x: Int, locale: Locale) -> String {
    var config = NumberFormatterConfig.defaultWholeNumberConfig
    config.locale = locale
    return NumberFormatterConfig.withFormatter(forConfig: config) { formatter in
      return formatter.string(for: x) ?? String(x)
    }
  }

  /**
   Formats an int percentage into a string.

   - parameter percentage: An int where 100 corresponds to 100%.
   - parameter env:        An (optional) environment.

   - returns: A formatted string.
   */
  public static func percentage(_ percentage: Int, env: Environment = AppEnvironment.current) -> String {
    return Format.percentage(Double(percentage) / 100.0, env: env)
  }

  /**
   Formats a Double percentage into a string.

   - parameter percentage: A Double where .10 corresponds to 10%.
   - parameter env:        An (optional) environment.

   - returns: A formatted string.
   */
  public static func percentage(_ percentage: Double, env: Environment = AppEnvironment.current) -> String {
    self.percentage(percentage, locale: env.locale)
  }

  public static func percentage(_ percentage: Int, locale: Locale) -> String {
    self.percentage(Double(percentage) / 100.0, locale: locale)
  }

  public static func percentage(_ percentage: Double, locale: Locale) -> String {
    var config = NumberFormatterConfig.defaultPercentageConfig
    config.locale = locale
    return NumberFormatterConfig.withFormatter(forConfig: config) { formatter in
      return formatter.string(for: percentage) ?? (String(percentage) + "%")
    }
  }

  /**
    Formats a Double currency amount into a string.

   - parameter amount: A Double associated with a currency amount

   - returns: A formatted string with 2 fraction digits
   */

  public static func decimalCurrency(for amount: Double) -> String {
    return NumberFormatterConfig.withFormatter(
      forConfig: .defaultDecimalCurrencyConfig
    ) { formatter in
      return formatter.string(for: amount) ?? String(format: "%.2f", amount)
    }
  }

  /**
   Formats an int with currency symbol into a string.

   - parameter amount: The amount to format.
   - parameter country: The country that currency is in.
   - parameter omitCurrencyCode: Pass true if you want to force the currency code to be omitted when trying
                                 to disambiguate currencies.
   - parameter env: (optional) An environment to use for locality.

   - returns: A formatted string.
   */
  public static func currency(
    _ amount: Int,
    currencyCode: String,
    omitCurrencyCode: Bool = true,
    env: Environment = AppEnvironment.current
  ) -> String {
    return Format.formattedCurrency(
      amount,
      currencyCode: currencyCode,
      omitCurrencyCode: omitCurrencyCode,
      env: env
    )
  }

  public static func currency(
    _ amount: Double,
    currencyCode: String,
    omitCurrencyCode: Bool = true,
    roundingMode: NumberFormatter.RoundingMode = .down,
    maximumFractionDigits: Int = 0,
    minimumFractionDigits: Int = 0,
    env: Environment = AppEnvironment.current
  ) -> String {
    return Format.formattedCurrency(
      amount,
      currencyCode: currencyCode,
      omitCurrencyCode: omitCurrencyCode,
      roundingMode: roundingMode,
      maximumFractionDigits: maximumFractionDigits,
      minimumFractionDigits: minimumFractionDigits,
      env: env
    )
  }

  public static func formattedCurrency(
    _ amount: Any,
    currencyCode: String,
    omitCurrencyCode: Bool = true,
    roundingMode: NumberFormatter.RoundingMode = .down,
    maximumFractionDigits: Int = 0,
    minimumFractionDigits: Int = 0,
    env: Environment = AppEnvironment.current
  ) -> String {
    let symbol = currencySymbol(
      forCurrencyCode: currencyCode,
      omitCurrencyCode: omitCurrencyCode,
      env: env
    )

    return self.formattedCurrency(
      amount, symbol: symbol, locale: env.locale, roundingMode: roundingMode,
      maximumFractionDigits: maximumFractionDigits, minimumFractionDigits: minimumFractionDigits
    )
  }

  /// Render resolved currency inputs without retaining a service/session environment.
  public static func formattedCurrency(
    _ amount: Any,
    symbol: String,
    locale: Locale,
    roundingMode: NumberFormatter.RoundingMode = .down,
    maximumFractionDigits: Int = 0,
    minimumFractionDigits: Int = 0
  ) -> String {
    var config = NumberFormatterConfig.defaultCurrencyConfig
    config.roundingMode = roundingMode
    config.maximumFractionDigits = maximumFractionDigits
    config.minimumFractionDigits = minimumFractionDigits
    config.locale = locale
    config.currencySymbol = symbol
    return NumberFormatterConfig.withFormatter(forConfig: config) { formatter in
      return formatter.string(for: amount)?
        .trimmed()
        .replacingOccurrences(of: String.nbsp + String.nbsp, with: String.nbsp)
        ?? (symbol + "\(amount)")
    }
  }

  public static func attributedCurrency(
    _ amount: Double,
    currencyCode: String,
    omitCurrencyCode: Bool = true,
    defaultAttributes: String.Attributes = [:],
    superscriptAttributes: String.Attributes = [:],
    maximumFractionDigits: Int = 2,
    minimumFractionDigits: Int = 2,
    env: Environment = AppEnvironment.current
  ) -> NSAttributedString? {
    let symbol = currencySymbol(forCurrencyCode: currencyCode, omitCurrencyCode: omitCurrencyCode, env: env)
    return self.attributedCurrency(
      amount, symbol: symbol, locale: env.locale,
      defaultAttributes: defaultAttributes, superscriptAttributes: superscriptAttributes,
      maximumFractionDigits: maximumFractionDigits, minimumFractionDigits: minimumFractionDigits
    )
  }

  /// Render already-resolved currency values without consulting global dependencies.
  public static func attributedCurrency(
    _ amount: Double,
    symbol: String,
    locale: Locale,
    defaultAttributes: String.Attributes = [:],
    superscriptAttributes: String.Attributes = [:],
    maximumFractionDigits: Int = 2,
    minimumFractionDigits: Int = 2
  ) -> NSAttributedString? {
    var config = NumberFormatterConfig.defaultCurrencyConfig
    config.locale = locale
    config.currencySymbol = symbol
    config.minimumFractionDigits = maximumFractionDigits
    config.maximumFractionDigits = minimumFractionDigits

    // Styling belongs to this request and must not mutate a cached formatter.
    let formatter = config.formatter()

    _ = formatter
      |> \.defaultAttributes .~ defaultAttributes
      |> \.currencySymbolAttributes .~ superscriptAttributes
      |> \.decimalSeparatorAttributes .~ superscriptAttributes
      |> \.fractionDigitsAttributes .~ superscriptAttributes

    return formatter.attributedString(for: amount)
  }

  public static func attributedPlusSign(_ attributes: String.Attributes = [:]) -> NSAttributedString {
    return NSAttributedString(string: Strings.plus_shipping_cost(shipping_cost: ""), attributes: attributes)
  }

  /**
   Create a date from a string with the given format

    - parameter dateString: The date string to convert to a Date
    - parameter dateFormat: The format the date string is in ex. "yyyy-MM-DD".
    - parameter timeZone: (optional) The timeZone the Date should be in.
    - parameter env: (optional) An environment to use for locality and time zones.

    - returns: A Date object with the specified time zone and locality.
   */
  public static func date(
    from dateString: String,
    dateFormat: String,
    timeZone: TimeZone? = nil,
    env: Environment = AppEnvironment.current
  ) -> Foundation.Date? {
    self.date(from: dateString, dateFormat: dateFormat, locale: env.locale,
              timeZone: timeZone ?? env.calendar.timeZone)
  }

  public static func date(
    from dateString: String,
    dateFormat: String,
    locale: Locale,
    timeZone: TimeZone
  ) -> Foundation.Date? {
    return DateFormatterConfig.withFormatter(
      forConfig: .init(
        dateFormat: dateFormat,
        dateStyle: nil,
        locale: locale,
        template: nil,
        timeStyle: nil,
        timeZone: timeZone
      )
    ) { formatter in
      return formatter.date(from: dateString)
    }
  }

  /**
   Format a date into a string.

   - parameter secondsInUTC: Seconds represention of the date as measured from UTC.
   - parameter dateStyle: (optional) The style to format the date.
   - parameter timeStyle: (optional) The style to format the time.
   - parameter env: (optional) An environment to use for locality and time zones.

   - returns: A formatted string.
   */
  public static func date(
    secondsInUTC seconds: TimeInterval,
    dateStyle: DateFormatter.Style = .medium,
    timeStyle: DateFormatter.Style = .medium,
    timeZone: TimeZone? = nil,
    env: Environment = AppEnvironment.current
  ) -> String {
    self.date(
      env.dateType.init(timeIntervalSince1970: seconds).date,
      dateStyle: dateStyle, timeStyle: timeStyle, locale: env.locale,
      timeZone: timeZone ?? env.calendar.timeZone
    )
  }

  public static func date(
    _ date: Foundation.Date,
    dateStyle: DateFormatter.Style,
    timeStyle: DateFormatter.Style,
    locale: Locale,
    timeZone: TimeZone
  ) -> String {
    return DateFormatterConfig.withFormatter(
      forConfig: .init(
        dateFormat: nil,
        dateStyle: dateStyle,
        locale: locale,
        template: nil,
        timeStyle: timeStyle,
        timeZone: timeZone
      )
    ) { formatter in
      return formatter.string(from: date)
    }
  }

  /**
   Format a date into a string.

   - parameter secondsInUTC: Seconds represention of the date as measured from UTC.
   - parameter template: A localized template string.

   - returns: A formatted string.
   */
  public static func date(
    secondsInUTC seconds: TimeInterval,
    template: String,
    timeZone: TimeZone? = nil
  ) -> String {
    let environment: Environment = AppEnvironment.current
    return self.date(
      environment.dateType.init(timeIntervalSince1970: seconds).date,
      template: template, locale: environment.locale,
      timeZone: timeZone ?? environment.calendar.timeZone
    )
  }

  /// Render a date snapshot without consulting global dependencies.
  public static func date(
    _ date: Foundation.Date,
    template: String,
    locale: Locale,
    timeZone: TimeZone
  ) -> String {
    return DateFormatterConfig.withFormatter(
      forConfig: .init(
        dateFormat: nil, dateStyle: nil, locale: locale, template: template,
        timeStyle: nil, timeZone: timeZone
      )
    ) { formatter in
      formatter.string(from: date)
    }
  }

  /**
   Format a duration into a string, i.e. "20 days", "14 hours", etc...

   - parameter seconds: Seconds represention of the date as measured from UTC.
   - parameter useToGo: If true, a localized "to go" will be appended to the unit so that it reads
                        "20 days to go", etc.
   - parameter abbreviate: Determines if an abbreviated version of the time unit string will be used.
   - parameter env: An (optional) environment.

   - returns: A pair of strings for the numeric time value and unit.
   */
  public static func duration(
    secondsInUTC seconds: TimeInterval,
    abbreviate: Bool = false,
    useToGo: Bool = false,
    env: Environment = AppEnvironment.current
  ) -> (time: String, unit: String) {
    self.duration(
      from: env.dateType.init().date,
      to: env.dateType.init(timeIntervalSince1970: seconds).date,
      calendar: env.calendar, abbreviate: abbreviate, useToGo: useToGo
    )
  }

  /// Calculate remaining time from captured clock/calendar values.
  public static func duration(
    from now: Foundation.Date,
    to deadline: Foundation.Date,
    calendar: Calendar,
    abbreviate: Bool = false,
    useToGo: Bool = false
  ) -> (time: String, unit: String) {
    let components = calendar.dateComponents(
      [.day, .hour, .minute, .second], from: now, to: deadline
    )

    let (day, hour, minute, second) = (
      components.day ?? 0,
      components.hour ?? 0,
      components.minute ?? 0,
      components.second ?? 0
    )

    let string: String
    if day > 1 {
      string = abbreviate
        ? Strings.dates_time_days_abbreviated(time_count: day)
        : Strings.dates_time_days(time_count: day)
    } else if day == 1 || hour > 0 {
      let count = day * 24 + hour
      string = abbreviate
        ? Strings.dates_time_hours_abbreviated(time_count: count)
        : Strings.dates_time_hours(time_count: count)
    } else if minute > 0, second >= 0 {
      string = abbreviate
        ? Strings.dates_time_minutes_abbreviated(time_count: minute)
        : Strings.dates_time_minutes(time_count: minute)
    } else if second <= 0 {
      string = "0 " + Strings.discovery_baseball_card_deadline_units_secs()
    } else {
      string = ""
    }

    let split = string
      .replacingOccurrences(of: "(\\d+) *", with: "$1 ", options: .regularExpression)
      .components(separatedBy: " ")

    guard split.count >= 1 else { return ("", "") }

    let result = (
      time: split.first ?? "",
      unit: split.suffix(from: 1).joined(separator: " ")
    )

    if useToGo {
      return (
        time: result.time,
        unit: Strings.discovery_baseball_card_time_left_to_go(time_left: result.unit)
      )
    }
    return result
  }

  /**
   Format a date into a relative string.

   - parameter secondsInUTC: Seconds represention of the date as measured from UTC.
   - parameter abbreviate: (optional) Whether or not to use the abbreviated style.
   - parameter threshold: (optional) Threshold.
   - parameter env: An (optional) environment.

   - returns: A formatted string.
   */
  public static func relative(
    secondsInUTC seconds: TimeInterval,
    abbreviate: Bool = false,
    threshold thresholdInDays: Int = defaultThresholdInDays,
    timeZone: TimeZone? = nil,
    env: Environment = AppEnvironment.current
  ) -> String {
    self.relative(
      env.dateType.init(timeIntervalSince1970: seconds).date,
      relativeTo: env.dateType.init().date, calendar: env.calendar, locale: env.locale,
      abbreviate: abbreviate, threshold: thresholdInDays,
      timeZone: timeZone ?? env.calendar.timeZone
    )
  }

  public static func relative(
    _ date: Foundation.Date,
    relativeTo now: Foundation.Date,
    calendar: Calendar,
    locale: Locale,
    abbreviate: Bool = false,
    threshold thresholdInDays: Int = defaultThresholdInDays,
    timeZone: TimeZone
  ) -> String {
    let components = calendar.dateComponents(
      [.day, .hour, .minute, .second], from: date, to: now
    )

    let (day, hour, minute, second) = (
      components.day ?? 0,
      components.hour ?? 0,
      components.minute ?? 0,
      components.second ?? 0
    )

    if abs(day) > thresholdInDays {
      return Format.date(
        date, dateStyle: .medium, timeStyle: .none, locale: locale, timeZone: timeZone
      )
    } else if day > 1 {
      return abbreviate
        ? Strings.dates_time_days_ago_abbreviated(time_count: day)
        : Strings.dates_time_days_ago(time_count: day)
    } else if day == 1 {
      return Strings.dates_yesterday()
    } else if hour > 0 {
      return abbreviate
        ? Strings.dates_time_hours_ago_abbreviated(time_count: hour)
        : Strings.dates_time_hours_ago(time_count: hour)
    } else if minute > 0 {
      return abbreviate
        ? Strings.dates_time_minutes_ago_abbreviated(time_count: minute)
        : Strings.dates_time_minutes_ago(time_count: minute)
    } else if second > 0 {
      return Strings.dates_just_now()
    } else if day < 0 {
      return abbreviate
        ? Strings.dates_time_in_days_abbreviated(time_count: -day)
        : Strings.dates_time_in_days(time_count: -day)
    } else if hour < 0 {
      return abbreviate
        ? Strings.dates_time_in_hours_abbreviated(time_count: -hour)
        : Strings.dates_time_in_hours(time_count: -hour)
    } else if minute < 0 {
      return abbreviate
        ? Strings.dates_time_in_minutes_abbreviated(time_count: -minute)
        : Strings.dates_time_in_minutes(time_count: -minute)
    } else {
      return Strings.dates_right_now()
    }
  }

  /**
   Formats a GraphAPI.MoneyFragment into a formatted currency string.

   - parameter money: The GraphAPI.MoneyFragment containing amount and currency symbol
   - parameter env: (optional) An environment to use for locality

   - returns: A formatted string with the appropriate currency symbol and amount, or nil if the fragment is incomplete
   */
  public static func currency(
    _ money: GraphAPI.MoneyFragment,
    env: Environment = AppEnvironment.current
  ) -> String? {
    guard
      case let .case(currency) = money.currency,
      let amountString = money.amount,
      let decimal = try? Decimal(amountString, format: .number)
    else { return nil }

    return decimal.formatted(
      .currency(code: currency.rawValue)
        .locale(env.locale)
    )
  }
}

public let defaultThresholdInDays = 30 // days

internal struct DateFormatterConfig: Hashable, Sendable {
  let dateFormat: String?
  fileprivate let dateStyle: DateFormatter.Style?
  fileprivate let locale: Locale
  fileprivate let template: String?
  fileprivate let timeStyle: DateFormatter.Style?
  fileprivate let timeZone: TimeZone

  fileprivate func formatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = self.locale
    formatter.timeZone = self.timeZone
    if let template = self.template {
      formatter.setLocalizedDateFormatFromTemplate(template)
    }
    if let dateFormat = self.dateFormat {
      formatter.dateFormat = dateFormat
    }
    if let dateStyle = self.dateStyle {
      formatter.dateStyle = dateStyle
    }
    if let timeStyle = self.timeStyle {
      formatter.timeStyle = timeStyle
    }
    return formatter
  }

  private static let formatters = Mutex<[DateFormatterConfig: DateFormatter]>([:])

  fileprivate static func withFormatter<Result: Sendable>(
    forConfig config: DateFormatterConfig,
    _ operation: (DateFormatter) -> Result
  ) -> Result {
    self.formatters.withLock { formatters in
      let formatter = formatters[config] ?? config.formatter()
      formatters[config] = formatter
      return operation(formatter)
    }
  }
}

private struct NumberFormatterConfig: Sendable {
  fileprivate var numberStyle: NumberFormatter.Style
  fileprivate var roundingMode: NumberFormatter.RoundingMode
  fileprivate var maximumFractionDigits: Int
  fileprivate var minimumFractionDigits: Int
  fileprivate var generatesDecimalNumbers: Bool
  fileprivate var locale: Locale
  fileprivate var currencySymbol: String

  fileprivate func formatter() -> AttributedNumberFormatter {
    let formatter = AttributedNumberFormatter()
    formatter.numberStyle = self.numberStyle
    formatter.roundingMode = self.roundingMode
    formatter.maximumFractionDigits = self.maximumFractionDigits
    formatter.minimumFractionDigits = self.minimumFractionDigits
    formatter.generatesDecimalNumbers = self.generatesDecimalNumbers
    formatter.locale = self.locale
    formatter.currencySymbol = self.currencySymbol
    return formatter
  }

  private static let formatters = Mutex<[NumberFormatterConfig: NumberFormatter]>([:])

  fileprivate static let defaultWholeNumberConfig = NumberFormatterConfig(
    numberStyle: .decimal,
    roundingMode: .down,
    maximumFractionDigits: 0,
    minimumFractionDigits: 0,
    generatesDecimalNumbers: false,
    locale: .current,
    currencySymbol: "$"
  )

  fileprivate static let defaultPercentageConfig = NumberFormatterConfig(
    numberStyle: .percent,
    roundingMode: .down,
    maximumFractionDigits: 0,
    minimumFractionDigits: 0,
    generatesDecimalNumbers: false,
    locale: .current,
    currencySymbol: "$"
  )

  fileprivate static let defaultCurrencyConfig = NumberFormatterConfig(
    numberStyle: .currency,
    roundingMode: .down,
    maximumFractionDigits: 0,
    minimumFractionDigits: 0,
    generatesDecimalNumbers: false,
    locale: .current,
    currencySymbol: "$"
  )

  fileprivate static let defaultDecimalCurrencyConfig = NumberFormatterConfig(
    numberStyle: .decimal,
    roundingMode: .down,
    maximumFractionDigits: 2,
    minimumFractionDigits: 2,
    generatesDecimalNumbers: false,
    // Decimal currency amounts are always formatted using En locale for compatibility with the API
    locale: Locale(identifier: "en"),
    currencySymbol: "$"
  )

  fileprivate static func withFormatter<Result: Sendable>(
    forConfig config: NumberFormatterConfig,
    _ operation: (NumberFormatter) -> Result
  ) -> Result {
    self.formatters.withLock { formatters in
      let formatter = formatters[config] ?? config.formatter()
      formatters[config] = formatter
      return operation(formatter)
    }
  }
}

extension NumberFormatterConfig: Hashable {
  fileprivate func hash(into hasher: inout Hasher) {
    hasher.combine(self.numberStyle)
    hasher.combine(self.roundingMode)
    hasher.combine(self.maximumFractionDigits)
    hasher.combine(self.minimumFractionDigits)
    hasher.combine(self.generatesDecimalNumbers)
    hasher.combine(self.locale)
    hasher.combine(self.currencySymbol)
  }
}

private func == (lhs: NumberFormatterConfig, rhs: NumberFormatterConfig) -> Bool {
  return
    lhs.numberStyle == rhs.numberStyle
      && lhs.roundingMode == rhs.roundingMode
      && lhs.maximumFractionDigits == rhs.maximumFractionDigits
      && lhs.minimumFractionDigits == rhs.minimumFractionDigits
      && lhs.generatesDecimalNumbers == rhs.generatesDecimalNumbers
      && lhs.locale == rhs.locale
      && lhs.currencySymbol == rhs.currencySymbol
}
