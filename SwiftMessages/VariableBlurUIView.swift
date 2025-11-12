import CoreImage.CIFilterBuiltins
import QuartzCore
import UIKit

/// credit https://github.com/jtrivedi/VariableBlurView
open class VariableBlurUIView: UIVisualEffectView {
    private var variableBlurFilter: NSObject?
    private var _maxBlurRadius: CGFloat = 20
    
    /// 最大模糊半径，可以动态修改
    public var maxBlurRadius: CGFloat {
        get { _maxBlurRadius }
        set {
            _maxBlurRadius = newValue
            variableBlurFilter?.setValue(newValue, forKey: "inputRadius")
        }
    }
    
    public init(
        maxBlurRadius: CGFloat = 20,
        alpha: CGFloat = 0.5
    ) {
        super.init(effect: UIBlurEffect(style: .regular))
        
            // `CAFilter` is a private QuartzCore class that dynamically create using Objective-C runtime.
        guard let CAFilter = NSClassFromString("CAFilter")! as? NSObject.Type else {
            print("[VariableBlur] Error: Can't find CAFilter class")
            return
        }
        guard
            let variableBlur = CAFilter.perform(NSSelectorFromString("filterWithType:"), with: "variableBlur")
                .takeUnretainedValue() as? NSObject
        else {
            print("[VariableBlur] Error: CAFilter can't create filterWithType: variableBlur")
            return
        }
        
            // The blur radius at each pixel depends on the alpha value of the corresponding pixel in the gradient mask.
            // An alpha of 1 results in the max blur radius, while an alpha of 0 is completely unblurred.
        let gradientImage = makeGradientImage(alpha: alpha)
        
        self._maxBlurRadius = maxBlurRadius
        self.variableBlurFilter = variableBlur
        
        variableBlur.setValue(maxBlurRadius, forKey: "inputRadius")
        variableBlur.setValue(gradientImage, forKey: "inputMaskImage")
        variableBlur.setValue(true, forKey: "inputNormalizeEdges")
        
            // We use a `UIVisualEffectView` here purely to get access to its `CABackdropLayer`,
            // which is able to apply various, real-time CAFilters onto the views underneath.
        let backdropLayer = subviews.first?.layer
        
            // Replace the standard filters (i.e. `gaussianBlur`, `colorSaturate`, etc.) with only the variableBlur.
        backdropLayer?.filters = [variableBlur]
        
            // Get rid of the visual effect view's dimming/tint view, so we don't see a hard line.
        for subview in subviews.dropFirst() {
            subview.alpha = 0
        }
    }
    
    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override open func didMoveToWindow() {
            // fixes visible pixelization at unblurred edge (https://github.com/nikstar/VariableBlur/issues/1)
        guard let window, let backdropLayer = subviews.first?.layer else {
            return
        }
        backdropLayer.setValue(window.traitCollection.displayScale, forKey: "scale")
    }
    
    override open func traitCollectionDidChange(_: UITraitCollection?) {
            // `super.traitCollectionDidChange(previousTraitCollection)` crashes the app
    }
    
    private func makeGradientImage(
        width: CGFloat = 100,
        height: CGFloat = 100,
        alpha: CGFloat
    )
    -> CGImage { // much lower resolution might be acceptable
                 // 使用纯色来产生统一的模糊效果，alpha 控制模糊强度 (0 = 无模糊，1 = 最大模糊)
        guard let solidColorFilter = CIFilter(name: "CIConstantColorGenerator") else {
            fatalError("Failed to create CIConstantColorGenerator filter")
        }
        solidColorFilter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: alpha), forKey: "inputColor")
        
        return CIContext().createCGImage(
            solidColorFilter.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: width, height: height)),
            from: CGRect(x: 0, y: 0, width: width, height: height)
        )!
    }
}
