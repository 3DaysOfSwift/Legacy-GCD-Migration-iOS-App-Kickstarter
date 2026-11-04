import KDS

import SwiftUI

enum FocusField {
  case newEmail
  case currentPassword
}

struct ChangeEmailView: View {
  @SwiftUI.Environment(\.defaultMinListRowHeight) var minListRow
  @FocusState private var focusField: FocusField?
  private let contentPadding = Spacing.unit_03
  @State private var viewModel = ChangeEmailScreenModel()
  @State private var retrievedEmailText = ""
  @State private var newEmailText = ""
  @State private var newPasswordText = ""
  @State private var saveEnabled = false
  @State private var showLoading = false
  @State private var showBannerMessage = false
  @State private var bannerMessage: MessageBannerViewViewModel?

  var body: some View {
    GeometryReader { proxy in
      List {
        LegacyColors.ksr_support_100.swiftUIColor()
          .frame(maxWidth: .infinity, maxHeight: self.minListRow, alignment: .center)
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets())

        VStack(alignment: .center, spacing: 0) {
          InputFieldView(
            titleText: Strings.Current_email(),
            secureField: false,
            placeholderText: "",
            contentPadding: self.contentPadding,
            valueText: self.$retrievedEmailText
          )
          .currentEmail()
          .onChange(of: self.viewModel.currentEmail) { newValue in
            self.retrievedEmailText = newValue
          }

          LegacyColors.ksr_cell_separator.swiftUIColor().frame(maxWidth: .infinity, maxHeight: 1)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())

        if !self.viewModel.hideMessageLabel {
          self.warningLabel(
            text: self.viewModel.warningMessageWithAlert.0,
            self.viewModel.warningMessageWithAlert.1
          )
          .frame(maxWidth: .infinity, maxHeight: self.minListRow, alignment: .leading)
          .background(LegacyColors.ksr_support_100.swiftUIColor())
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets())
        }

        if !self.viewModel.hideVerifyView {
          VStack(alignment: .leading, spacing: 0) {
            Button(self.viewModel.verifyEmailButtonTitle) {
              self.viewModel.resendVerificationEmail()
            }
            .font(Font(UIFont.ksr_body()))
            .foregroundColor(LegacyColors.ksr_create_700.swiftUIColor())
            .padding(self.contentPadding)
            .disabled(self.showLoading)

            LegacyColors.ksr_cell_separator.swiftUIColor().frame(maxWidth: .infinity, maxHeight: 1)
          }
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets())
        }

        LegacyColors.ksr_support_100.swiftUIColor()
          .frame(maxWidth: .infinity, maxHeight: self.minListRow, alignment: .center)
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets())

        VStack(alignment: .center, spacing: 0) {
          InputFieldView(
            titleText: Strings.New_email(),
            secureField: false,
            placeholderText: Strings.login_placeholder_email(),
            contentPadding: self.contentPadding,
            valueText: self.$newEmailText
          )
          .onChange(of: self.viewModel.newEmail) { newValue in
            self.newEmailText = newValue
          }
          .onChange(of: self.newEmailText) { newValue in
            self.viewModel.newEmail = newValue
          }
          .newEmail(editable: !self.showLoading)
          .focused(self.$focusField, equals: .newEmail)
          .onSubmit {
            self.focusField = .currentPassword
          }

          InputFieldView(
            titleText: Strings.Current_password(),
            secureField: true,
            placeholderText: Strings.login_placeholder_password(),
            contentPadding: self.contentPadding,
            valueText: self.$newPasswordText
          )
          .onChange(of: self.newPasswordText) { newValue in
            self.viewModel.password = newValue
          }
          .currentPassword(editable: !self.showLoading)
          .focused(self.$focusField, equals: .currentPassword)
          .onChange(of: self.viewModel.password) { newValue in
            self.newPasswordText = newValue
          }
          // FIXME: So "Done" on keyboard doesn't trigger Save --> in the future we might want to add this (was in the old `ChangeEmailViewController`)

          LegacyColors.ksr_cell_separator.swiftUIColor().frame(maxWidth: .infinity, maxHeight: 1)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
      }
      .navigationTitle(Strings.Change_email())
      .background(LegacyColors.ksr_support_100.swiftUIColor())
      .listStyle(.plain)
      .toolbar {
        self.saveButton
      }
      .overlay(alignment: .bottom) {
        MessageBannerView(viewModel: self.$bannerMessage)
          .frame(
            minWidth: proxy.size.width,
            idealWidth: proxy.size.width,
            maxHeight: proxy.size.height / 5,
            alignment: .bottom
          )
          .animation(.easeInOut)
      }
      .onChange(of: self.viewModel.bannerRevision) { _ in
        self.bannerMessage = self.viewModel.banner
      }
      .onAppear {
        self.viewModel.viewDidLoad()
      }
    }
  }

  @ToolbarContentBuilder
  private var saveButton: some ToolbarContent {
    let toolbarItem = ToolbarItem(placement: .navigationBarTrailing) {
      LoadingBarButtonItem(
        saveEnabled: self.$saveEnabled,
        showLoading: self.$showLoading,
        titleText: Strings.Save()
      ) {
        self.focusField = nil
        self.viewModel.save()
      }
      .onChange(of: self.viewModel.saveEnabled) { newValue in
        self.saveEnabled = newValue
      }
      .onChange(of: self.viewModel.isLoading) { newValue in
        self.showLoading = newValue
      }
    }
    if #available(iOS 26, *) {
      toolbarItem.sharedBackgroundVisibility(.hidden)
    } else {
      toolbarItem
    }
  }

  private struct InputFieldView: View {
    var titleText: String
    var secureField: Bool
    var placeholderText: String
    var contentPadding: CGFloat
    var valueText: Binding<String>

    var body: some View {
      HStack {
        Text(self.titleText)
          .frame(
            maxWidth: .infinity,
            alignment: .leading
          )
          .font(Font(UIFont.ksr_body()))
          .foregroundColor(LegacyColors.ksr_support_700.swiftUIColor())
        Spacer()

        InputFieldUserInputView(
          secureField: self.secureField,
          placeholderText: self.placeholderText,
          valueText: self.valueText
        )
      }
      .padding(self.contentPadding)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(self.titleText)
    }
  }

  private struct InputFieldUserInputView: View {
    var secureField: Bool
    var placeholderText: String
    var valueText: Binding<String>

    var body: some View {
      if self.secureField {
        SecureField(
          "",
          text: self.valueText,
          prompt: Text(self.placeholderText).foregroundColor(LegacyColors.ksr_support_400.swiftUIColor())
        )
      } else {
        TextField(
          "",
          text: self.valueText,
          prompt:
          Text(self.placeholderText).foregroundColor(LegacyColors.ksr_support_400.swiftUIColor())
        )
      }
    }
  }

  @ViewBuilder
  private func warningLabel(text: String, _ alert: Bool) -> some View {
    let textColor = alert ? LegacyColors.ksr_alert.swiftUIColor() : LegacyColors.ksr_support_400
      .swiftUIColor()

    Label(text, systemImage: "exclamationmark.triangle.fill")
      .labelStyle(.titleOnly)
      .font(Font(UIFont.ksr_body(size: 13)))
      .lineLimit(nil)
      .padding([.leading, .trailing], self.contentPadding)
      .foregroundColor(textColor)
  }
}
