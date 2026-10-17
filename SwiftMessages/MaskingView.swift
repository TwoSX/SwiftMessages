//
//  MaskingView.swift
//  SwiftMessages
//
//  Created by Timothy Moose on 3/11/17.
//  Copyright © 2017 SwiftKick Mobile. All rights reserved.
//

import UIKit


class MaskingView: PassthroughView {

    func install(keyboardTrackingView: KeyboardTrackingView) {
        self.keyboardTrackingView = keyboardTrackingView
        keyboardTrackingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyboardTrackingView)
        keyboardTrackingView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        keyboardTrackingView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        keyboardTrackingView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
    }

    var accessibleElements: [NSObject] = []

    weak var backgroundView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let view = backgroundView {
                view.isUserInteractionEnabled = false
                view.frame = bounds
                view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                addSubview(view)
                sendSubviewToBack(view)
            }
        }
    }

    override func accessibilityElementCount() -> Int {
        return accessibleElements.count
    }

    override func accessibilityElement(at index: Int) -> Any? {
        return accessibleElements[index]
    }

    override func index(ofAccessibilityElement element: Any) -> Int {
        guard let object = element as? NSObject else { return 0 }
        return accessibleElements.firstIndex(of: object) ?? 0
    }

    /// The horizontal area the message view should span. Equals the masking view's bounds,
    /// unless `divisionAvoidance` confines it to one side of an active vertical fold.
    let messageAreaLayoutGuide = UILayoutGuide()

    var divisionAvoidance: SwiftMessages.DivisionAvoidance = .disabled {
        didSet {
            guard divisionAvoidance != oldValue else { return }
            installHingeObservationIfNeeded()
            setNeedsLayout()
        }
    }

    private var messageAreaLeftConstraint: NSLayoutConstraint?
    private var messageAreaRightConstraint: NSLayoutConstraint?
    private var hingeInteraction: UIInteraction?

    init() {
        super.init(frame: CGRect.zero)
        initCommon()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initCommon()
    }

    private func initCommon() {
        clipsToBounds = true
        addLayoutGuide(messageAreaLayoutGuide)
        // Left/right rather than leading/trailing: reserved region frames are in
        // unflipped view coordinates.
        let left = messageAreaLayoutGuide.leftAnchor.constraint(equalTo: leftAnchor)
        let right = messageAreaLayoutGuide.rightAnchor.constraint(equalTo: rightAnchor)
        NSLayoutConstraint.activate([
            left,
            right,
            messageAreaLayoutGuide.topAnchor.constraint(equalTo: topAnchor),
            messageAreaLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        messageAreaLeftConstraint = left
        messageAreaRightConstraint = right
    }

    override func layoutSubviews() {
        // Adjust before super so the message view is laid out against the updated area.
        let areaChanged = updateMessageArea()
        super.layoutSubviews()
        // A new width can change the hosted content's height. Resolve it in this same pass, so it
        // shares the animation that drives the area change (the system's fold transition or ours)
        // instead of being animated separately afterwards.
        if areaChanged, synchronizeMessageContentSize() {
            updateConstraintsIfNeeded()
            super.layoutSubviews()
        }
    }

    // MARK: - Division avoidance

    /// Returns whether the message area changed.
    private func updateMessageArea() -> Bool {
        let (leftConstant, rightConstant) = messageAreaConstants()
        guard messageAreaLeftConstraint?.constant != leftConstant
                || messageAreaRightConstraint?.constant != rightConstant else { return false }
        messageAreaLeftConstraint?.constant = leftConstant
        messageAreaRightConstraint?.constant = rightConstant
        return true
    }

    private func synchronizeMessageContentSize() -> Bool {
        subviews
            .compactMap { $0 as? ContentSizeSynchronizing }
            .reduce(false) { $1.synchronizeContentSize() || $0 }
    }

    private func messageAreaConstants() -> (left: CGFloat, right: CGFloat) {
        let (minX, maxX) = messageAreaHorizontalBounds()
        return (minX, maxX - bounds.width)
    }

    /// Moves the message view to the current message area, animating position and size together.
    private func animateMessageAreaChange() {
        // Hinge angle updates arrive frequently; only animate when the area actually changes.
        let (leftConstant, rightConstant) = messageAreaConstants()
        guard window != nil,
              messageAreaLeftConstraint?.constant != leftConstant
                || messageAreaRightConstraint?.constant != rightConstant else { return }
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                self.setNeedsLayout()
                self.layoutIfNeeded()
            }
        )
    }

    private func messageAreaHorizontalBounds() -> (minX: CGFloat, maxX: CGFloat) {
        let fullWidth = (minX: CGFloat(0), maxX: bounds.width)
        guard divisionAvoidance != .disabled,
              #available(iOS 27.1, *) else { return fullWidth }
        // Only a vertical fold splits the content into left and right pages; a horizontal
        // fold (portrait) leaves bottom and center messages usable as is.
        guard let fold = reservedRegions(kind: .division)
            .first(where: { $0.isActive && $0.frame.height > $0.frame.width })?
            .frame,
              fold.minX > 0, fold.maxX < bounds.width else { return fullWidth }
        let isLeftToRight = effectiveUserInterfaceLayoutDirection == .leftToRight
        let placesOnLeft = (divisionAvoidance == .leading) == isLeftToRight
        // The message gets the whole page, like it gets the whole container when flat; its own
        // padding keeps it off the page edges.
        return placesOnLeft ? (0, fold.minX) : (fold.maxX, bounds.width)
    }

    private func installHingeObservationIfNeeded() {
        guard #available(iOS 27.1, *) else { return }
        if divisionAvoidance == .disabled {
            if let hingeInteraction {
                removeInteraction(hingeInteraction)
                self.hingeInteraction = nil
            }
            return
        }
        guard hingeInteraction == nil else { return }
        // UIKit normally lays this view out within the system's fold transition when the division
        // region changes. Folding doesn't necessarily change the bounds though, so the hinge is
        // observed as a fallback that animates any change the layout pass hasn't picked up yet.
        let interaction = UIHingeInteraction { [weak self] _, _ in
            self?.animateMessageAreaChange()
        }
        addInteraction(interaction)
        hingeInteraction = interaction
    }

    private var keyboardTrackingView: KeyboardTrackingView?

    override func addSubview(_ view: UIView) {
        super.addSubview(view)
        guard let keyboardTrackingView = keyboardTrackingView,
            view != keyboardTrackingView,
            view != backgroundView else { return }
        let offset: CGFloat
        if let adjustable = view as? MarginAdjustable {
            offset = -adjustable.bounceAnimationOffset
        } else {
            offset = 0
        }
        keyboardTrackingView.topAnchor.constraint(
            greaterThanOrEqualTo: view.bottomAnchor,
            constant: offset
        ).with(priority: UILayoutPriority(250)).isActive = true
    }
}

/// Implemented by message views whose height depends on their width, so that a width change
/// can be measured synchronously and animated together with it.
@MainActor
protocol ContentSizeSynchronizing: AnyObject {
    /// Lays out the content at the current width and invalidates the intrinsic content size
    /// if it changed. Returns whether it changed.
    func synchronizeContentSize() -> Bool
}
