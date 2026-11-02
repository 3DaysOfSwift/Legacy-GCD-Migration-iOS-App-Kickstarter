import Foundation

public struct SignInWithAppleEnvelope: Decodable, Sendable {
  public var signInWithApple: SignInWithApple

  public struct SignInWithApple: Decodable, Sendable {
    public var apiAccessToken: String
    public var user: SignInWithAppleEnvelope.User
  }

  public struct User: Decodable, Sendable {
    public var uid: String
  }
}
