import ApolloTestSupport
import GraphAPI
import GraphAPITestMocks
@testable import KsApi
@testable import KsApiTestHelpers
import XCTest

final class SignInWithAppleEnvelope_SignInWithAppleMutation_DataTests: XCTestCase {
  func testSignInWithAppleEnvelope_Data_Success() {
    let mock = Mock<GraphAPITestMocks.Mutation>()
    mock.signInWithApple = Mock<GraphAPITestMocks.SignInWithApplePayload>()
    mock.signInWithApple?.apiAccessToken = "foobar"
    mock.signInWithApple?.user = Mock<GraphAPITestMocks.User>()
    mock.signInWithApple?.user?.uid = "deadbeef"

    let data = GraphAPI.SignInWithAppleMutation.Data.from(mock)

    let env = SignInWithAppleEnvelope.from(data)

    XCTAssertEqual(env?.signInWithApple.apiAccessToken, "foobar")
    XCTAssertEqual(env?.signInWithApple.user.uid, "deadbeef")

  }

  func testSignInWithAppleEnvelope_Data_Failed() {
    let erroredData: GraphAPI.SignInWithAppleMutation.Data = try! testGraphObject(jsonString: "{}")
    XCTAssertNil(SignInWithAppleEnvelope.from(erroredData))
  }
}
