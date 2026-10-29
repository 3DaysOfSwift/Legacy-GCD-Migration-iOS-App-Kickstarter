import KsApi
import Library
import SwiftUI

private struct PaginationExampleProjectCell: View {
  let title: String
  var body: some View {
    Text(self.title)
  }
}

private struct PaginationExampleProjectList: View {
  let projects: [PaginationExampleViewModel.ProjectData]
  let showProgressView: Bool
  let statusText: String
  @State var selectedItem: PaginationExampleViewModel.ProjectData?

  let onRefresh: () async -> Void
  let onLoadMore: () async -> Void

  var body: some View {
    HStack {
      Spacer()
      Text("👉 \(self.statusText)")
      Spacer()
    }
    .padding(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
    .background(.purple)
    PaginatingList(
      data: self.projects,
      canLoadMore: self.showProgressView,
      selectedItem: self.$selectedItem
    ) { data in
      PaginationExampleProjectCell(title: data.title)
        .listItemTint(ListItemTint.fixed(.orange))
    } onRefresh: {
      await self.onRefresh()
    } onLoadMore: {
      await self.onLoadMore()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: self.selectedItem, perform: { value in
      if let value {
        print("Row tapped: \(value.title)")
        self.selectedItem = nil
      }
    })
  }
}

public struct PaginationExampleView: View {
  @State private var viewModel = PaginationExampleViewModel()

  public var body: some View {
    // Note that PaginationExampleProjectList is decoupled from the view model;
    // all the information it needs is passed in as a value snapshot.
    // This makes it easy to write a preview!
    PaginationExampleProjectList(
      projects: self.viewModel.projects,
      showProgressView: self.viewModel.showProgressView,
      statusText: self.viewModel.statusText,
      onRefresh: {
        await self.viewModel.refresh()
      },
      onLoadMore: {
        await self.viewModel.loadNextPage()
      }
    )
    .task { await self.viewModel.load() }
    .onDisappear { self.viewModel.suspend() }
  }
}

#Preview {
  PaginationExampleProjectList(
    projects: [
      .init(id: 1, title: "Cool project one"),
      .init(id: 2, title: "Cool project two"),
      .init(id: 3, title: "Cool project three")
    ],
    showProgressView: true,
    statusText: "Example status text",
    onRefresh: {}, onLoadMore: {}
  )
}
