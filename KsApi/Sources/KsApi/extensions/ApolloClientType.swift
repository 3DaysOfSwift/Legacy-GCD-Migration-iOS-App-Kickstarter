import ApolloAPI
import ReactiveSwift

public protocol ApolloClientType {
  func perform<Mutation: GraphQLMutation>(mutation: Mutation) -> SignalProducer<Mutation.Data, ErrorEnvelope>
}
