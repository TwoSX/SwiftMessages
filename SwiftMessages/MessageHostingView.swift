//
//  MessageHostingView.swift
//  SwiftMessages
//
//  Created by Timothy Moose on 10/5/23.
//

import SwiftUI
import UIKit

/// A rudimentary hosting view for SwiftUI messages.
@available(iOS 14.0, *)
public class MessageHostingView<Content>: UIView, Identifiable, MarginAdjustable where Content: View {

    // MARK: - API

    public let id: String
    
    /// 是否忽略 UIHostingController 的安全区域限制，让 SwiftUI 内容可以使用 .edgesIgnoringSafeArea() 等修饰符来控制。
    /// 注意：此属性仅在 iOS 16.4+ 上生效。
    public let ignoresSafeAreaRegions: Bool
    
    // MARK: - MarginAdjustable
    
    public var layoutMarginAdditions: UIEdgeInsets = .zero
    public var collapseLayoutMarginAdditions: Bool = false
    public var respectSafeArea: Bool = false
    public var bounceAnimationOffset: CGFloat = 0 // 不使用弹跳动画偏移

    public init(id: String, content: Content, ignoresSafeAreaRegions: Bool = false) {
        self.id = id
        self.content = { _ in content }
        self.ignoresSafeAreaRegions = ignoresSafeAreaRegions
        self.bounceAnimationOffset = ignoresSafeAreaRegions ? 0 : 5
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    public init<Message>(
        message: Message,
        ignoresSafeAreaRegions: Bool = false,
        @ViewBuilder content: @escaping (Message, MessageGeometryProxy) -> Content
    ) where Message: Identifiable {
        self.id = message.id
        self.content = { geom in content(message, geom) }
        self.ignoresSafeAreaRegions = ignoresSafeAreaRegions
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    convenience public init<Message>(message: Message, ignoresSafeAreaRegions: Bool = false) where Message: MessageViewConvertible, Message.Content == Content {
        self.init(id: message.id, content: message.asMessageView(), ignoresSafeAreaRegions: ignoresSafeAreaRegions)
    }

    // MARK: - Constants

    // MARK: - Variables

    private var hostVC: UIHostingController<Content>?
    private let content: (MessageGeometryProxy) -> Content
    private var lastKnownSize: CGSize = .zero
    private var isUpdatingLayout: Bool = false
    private var pendingLayoutUpdate: DispatchWorkItem?

    // MARK: - Lifecycle

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Override hit testing so that only SwiftUI-rendered content inside `MessageHostingView` can receive touches.
    ///
    /// Background:
    /// - `MessageHostingView` does not tightly wrap its SwiftUI content, potentially leaving surrounding regions that should not be tappable. There have
    ///   been some complications with detecting touches on the SwiftUI content over the years that have led to the current approach:
    /// - On iOS 18, UIKit performs a second hit test that resolves to the `UIHostingController`'s view instead of the actual SwiftUI element.
    /// - On iOS 26, the `UIHostingController`'s view no longer contains any subviews, but its `CALayer` *layer* hierarchy still reflects the SwiftUI content.
    ///
    /// All of these issues can be solved by hit testing the layer hierarchy instead of the view hierarchy:
    /// - Call `super.hitTest(point, with: event)` to obtain a candidate view `view`. If our heuristic determines that SwiftUI content was tapped,
    ///   then we return `view` to accept the touch. Otherwise, return `nil` to pass the touch through.
    /// - If the candidate is `MessageHostingView` return `nil`.
    /// - If the candidate is directly parented to `MessageHostingView`, this is the `UIHostingController` view containing the SwiftUI content.
    ///   To determine if SwiftUI content was touched, we iterate over hosting controller's sublayers and return the candidate if the touch intersects a sublayer.
    ///   Otherwise, return `nil`.
    /// - For any other case, we return the candidate because we don't know what's going on.
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let view = super.hitTest(point, with: event) else { return nil }
        if view == self { return nil }
        
        if view.superview == self {
            for sublayer in view.layer.sublayers ?? [] {
                let sublayerPoint = self.layer.convert(point, to: sublayer)
                if sublayer.contains(sublayerPoint) {
                    return view
                }
            }
            return nil
        }
        return view
    }

    public override func didMoveToSuperview() {
        guard let superview = self.superview else { return }
        
        let size = superview.bounds.size
        let insets = superview.safeAreaInsets
        let ltr = superview.effectiveUserInterfaceLayoutDirection == .leftToRight
        
        let proxy = MessageGeometryProxy(
            fullSize: size,
            size: CGSize(
                width: size.width - insets.left - insets.right,
                height: size.height - insets.top - insets.bottom
            ),
            safeAreaInsets: EdgeInsets(
                top: insets.top,
                leading: ltr ? insets.left : insets.right,
                bottom: insets.bottom,
                trailing: ltr ? insets.right : insets.left
            )
        )
        
        let hostVC = UIHostingController(rootView: content(proxy))
        self.hostVC = hostVC
        
        // iOS 16+ 使用 sizingOptions 来让内容自动调整大小
        if #available(iOS 16.0, *) {
            hostVC.sizingOptions = .intrinsicContentSize
        }
        
        // 禁用 UIHostingController 的安全区域限制，让 SwiftUI 内容自己控制
        // 注意：safeAreaRegions 属性仅在 iOS 16.4+ 上可用
        if ignoresSafeAreaRegions {
            if #available(iOS 16.4, *) {
                hostVC.safeAreaRegions = []
            }
        }
        
        hostVC.loadViewIfNeeded()
        installContentView(hostVC.view)
        hostVC.view.backgroundColor = .clear
    }
    
    public override var intrinsicContentSize: CGSize {
        hostVC?.view.intrinsicContentSize ?? super.intrinsicContentSize
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // 如果正在更新布局，不要触发新的布局更新，避免循环
        guard !isUpdatingLayout else { return }
        
        // 检查内容尺寸是否发生变化
        if let contentView = hostVC?.view {
            let newSize = contentView.intrinsicContentSize
            // 添加一个小的阈值（1.0 point），避免浮点数精度问题导致的无限循环
            let heightDiff = abs(newSize.height - lastKnownSize.height)
            let widthDiff = abs(newSize.width - lastKnownSize.width)
            
            if (heightDiff > 1.0 || widthDiff > 1.0) && newSize.height != UIView.noIntrinsicMetric {
                lastKnownSize = newSize
                invalidateIntrinsicContentSize()
                
                // 取消之前的待处理更新
                pendingLayoutUpdate?.cancel()
                
                // 延迟一点点再触发布局更新，让 SwiftUI 的动画稳定下来
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    
                    // 如果已经在更新中，跳过
                    guard !self.isUpdatingLayout else { return }
                    
                    self.isUpdatingLayout = true
                    
                    UIView.animate(withDuration: 0.3, animations: {
                        self.superview?.layoutIfNeeded()
                    }, completion: { [weak self] _ in
                        self?.isUpdatingLayout = false
                    })
                }
                
                pendingLayoutUpdate = workItem
                // 使用很短的延迟，让当前的布局周期完成
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
            }
        }
    }

    // MARK: - Configuration

    private func installContentView(_ contentView: UIView) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        
        // 当 ignoresSafeAreaRegions 为 true 时，让内容根据其 intrinsic size 自由布局
        // 这样 SwiftUI 中的 .padding() 等修饰符可以正确工作
        if ignoresSafeAreaRegions {
            // 左右约束使用等式，确保宽度正确
            let leadingConstraint = contentView.leadingAnchor.constraint(equalTo: leadingAnchor)
            let trailingConstraint = contentView.trailingAnchor.constraint(equalTo: trailingAnchor)
            
            // 顶部和底部使用等式约束，让 contentView 撑起 MessageHostingView 的大小
            let topConstraint = contentView.topAnchor.constraint(equalTo: topAnchor)
            let bottomConstraint = contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
            
            NSLayoutConstraint.activate([
                leadingConstraint,
                trailingConstraint,
                topConstraint,
                bottomConstraint,
            ])
            
            // 设置内容压缩阻力和拥抱优先级，防止被压缩
            contentView.setContentCompressionResistancePriority(.required, for: .vertical)
            contentView.setContentHuggingPriority(.required, for: .vertical)
        } else {
            NSLayoutConstraint.activate([
                contentView.topAnchor.constraint(equalTo: topAnchor),
                contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
                contentView.leftAnchor.constraint(equalTo: leftAnchor),
                contentView.rightAnchor.constraint(equalTo: rightAnchor),
            ])
        }
    }
}
