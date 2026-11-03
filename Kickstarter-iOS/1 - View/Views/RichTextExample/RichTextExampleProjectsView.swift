import KDS
import SwiftUI

internal struct RichTextExampleProjectsView: View {
  @State private var viewModel = RichTextExampleProjectsViewModel()
  private var onSelectProject: (RichTextExampleProjectsViewModel.ProjectItem) -> Void
  @State private var slug: String = ""

  init(onSelectProject: @escaping (RichTextExampleProjectsViewModel.ProjectItem) -> Void) {
    self.onSelectProject = onSelectProject
  }

  @ViewBuilder var directLinkField: some View {
    SwiftUI.Section {
      TextField("Project slug or URL (optional)", text: self.$slug)
        .autocorrectionDisabled()
        .autocapitalization(.none)
        .keyboardType(.URL)
        .onChange(of: self.slug) { _, _ in
          self.viewModel.clearLookup()
        }
        .onSubmit {
          self.viewModel.submit(input: self.slug, onSelect: self.onSelectProject)
        }
      if self.viewModel.slugError {
        Text("No project found")
          .foregroundStyle(Colors.Text.Accent.red.swiftUIColor())
      }
    }
  }

  var body: some View {
    List {
      self.directLinkField
      SwiftUI.Section {
        if self.viewModel.isLoading {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
          Text(error)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ForEach(self.viewModel.projects) { project in
            Button(project.name) {
              self.onSelectProject(project)
            }
          }
        }
      }
    }
    .navigationTitle("Rich Text Example")
    .task {
      await self.viewModel.loadProjects()
    }
    .onDisappear { self.viewModel.suspend() }
  }
}
