//
//  SwiftMessageModifier.swift
//  SwiftUIDemo
//
//  Created by Timothy Moose on 10/5/23.
//

import SwiftUI

@available(iOS 14.0, *)
public extension View {
    /// A view modifier for displaying a message using similar semantics to the `.sheet()` modifier.
    func swiftMessage<Message, MessageContent>(
        message: Binding<Message?>,
        config: SwiftMessages.Config? = nil,
        swiftMessages: SwiftMessages? = nil,
        ignoresSafeAreaRegions: Bool = false,
        @ViewBuilder messageContent: @escaping (Message) -> MessageContent
    ) -> some View where Message: Equatable & Identifiable, MessageContent: View {
        swiftMessage(message: message, config: config, swiftMessages: swiftMessages, ignoresSafeAreaRegions: ignoresSafeAreaRegions) { message, _ in
            messageContent(message)
        }
    }

    /// A view modifier for displaying a message using similar semantics to the `.sheet()` modifier. This variant provides a
    /// `SwiftMessageGeometryProxy`. The proxy is useful when one needs to know the geometry metrics of the container view,
    /// particularly because `GeometryReader` doesn't work inside the view builder due to the way the message view is being
    /// displayed from UIKit.
    func swiftMessage<Message, MessageContent>(
        message: Binding<Message?>,
        config: SwiftMessages.Config? = nil,
        swiftMessages: SwiftMessages? = nil,
        ignoresSafeAreaRegions: Bool = false,
        @ViewBuilder messageContent: @escaping (Message, MessageGeometryProxy) -> MessageContent
    ) -> some View where Message: Equatable & Identifiable, MessageContent: View {
        modifier(
            SwiftMessageModifier(
                message: message,
                config: config,
                swiftMessages: swiftMessages,
                ignoresSafeAreaRegions: ignoresSafeAreaRegions,
                messageContent: messageContent
            )
        )
    }

    /// A state-based modifier for displaying a message when `Message` conforms to `MessageViewConvertible`. This variant should be used if the message
    /// view can be represented as pure data. If the message requires a delegate, has callbacks, etc., consider using the variant that takes a message view builder.
    func swiftMessage<Message>(
        message: Binding<Message?>,
        config: SwiftMessages.Config? = nil,
        swiftMessages: SwiftMessages? = nil,
        ignoresSafeAreaRegions: Bool = false
    ) -> some View where Message: MessageViewConvertible {
        swiftMessage(message: message, config: config, swiftMessages: swiftMessages, ignoresSafeAreaRegions: ignoresSafeAreaRegions) { content in
            content.asMessageView()
        }
    }
}

@available(iOS 14.0, *)
private struct SwiftMessageModifier<Message, MessageContent>: ViewModifier where Message: Equatable & Identifiable, MessageContent: View {

    // MARK: - API

    fileprivate init(
        message: Binding<Message?>,
        config: SwiftMessages.Config? = nil,
        swiftMessages: SwiftMessages? = nil,
        ignoresSafeAreaRegions: Bool = false,
        @ViewBuilder messageContent: @escaping (Message) -> MessageContent
    ) {
        _message = message
        self.config = config
        self.swiftMessages = swiftMessages
        self.ignoresSafeAreaRegions = ignoresSafeAreaRegions
        self.messageContent = { message, _ in
            messageContent(message)
        }
    }

    fileprivate init(
        message: Binding<Message?>,
        config: SwiftMessages.Config? = nil,
        swiftMessages: SwiftMessages? = nil,
        ignoresSafeAreaRegions: Bool = false,
        @ViewBuilder messageContent: @escaping (Message, MessageGeometryProxy) -> MessageContent
    ) {
        _message = message
        self.config = config
        self.swiftMessages = swiftMessages
        self.ignoresSafeAreaRegions = ignoresSafeAreaRegions
        self.messageContent = messageContent
    }

    fileprivate init(
        message: Binding<Message?>,
        config: SwiftMessages.Config? = nil,
        swiftMessages: SwiftMessages? = nil,
        ignoresSafeAreaRegions: Bool = false
    ) where Message: MessageViewConvertible, Message.Content == MessageContent {
        _message = message
        self.config = config
        self.swiftMessages = swiftMessages
        self.ignoresSafeAreaRegions = ignoresSafeAreaRegions
        self.messageContent = { message, _ in
            message.asMessageView()
        }
    }

    // MARK: - Constants

    // MARK: - Variables

    @Binding private var message: Message?
    private let config: SwiftMessages.Config?
    private let swiftMessages: SwiftMessages?
    private let ignoresSafeAreaRegions: Bool
    @ViewBuilder private let messageContent: (Message, MessageGeometryProxy) -> MessageContent

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            .onChange(of: message) { message in
                let show: @MainActor (SwiftMessages.Config, UIView) -> Void = swiftMessages?.show(config:view:) ?? SwiftMessages.show(config:view:)
                let hideAll: @MainActor () -> Void = swiftMessages?.hideAll ?? SwiftMessages.hideAll
                switch message {
                case let message?:
                    let view = MessageHostingView(message: message, ignoresSafeAreaRegions: ignoresSafeAreaRegions, content: messageContent)
                    var config = config ?? swiftMessages?.defaultConfig ?? SwiftMessages.defaultConfig
                    config.eventListeners.append { event in
                        if case .didHide = event, event.id == self.message?.id {
                            self.message = nil
                        }
                    }
                    hideAll()
                    show(config, view)
                case .none:
                    hideAll()
                }
            }
    }
}
