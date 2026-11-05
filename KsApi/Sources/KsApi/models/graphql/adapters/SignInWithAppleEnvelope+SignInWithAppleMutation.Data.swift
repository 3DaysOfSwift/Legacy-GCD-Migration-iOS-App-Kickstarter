import Foundation
import GraphAPI

extension SignInWithAppleEnvelope {
  /**
   Map `GraphAPI.SignInWithAppleMutation.Data` to a `SignInWithAppleEnvelope`, otherwise return `nil`
   */
  static func from(_ data: GraphAPI.SignInWithAppleMutation.Data) -> SignInWithAppleEnvelope? {
    guard let signInWithApple = data.signInWithApple,
          let apiAccessToken = signInWithApple.apiAccessToken,
          let user = signInWithApple.user else {
      return nil
    }

    return SignInWithAppleEnvelope(signInWithApple: SignInWithApple(
      apiAccessToken: apiAccessToken,
      user: User(uid: user.uid)
    ))
  }

}
